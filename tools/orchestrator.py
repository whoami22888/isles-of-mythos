#!/usr/bin/env python3
"""Checkpointing task orchestrator (IOM-00).

Runs an ordered plan of commands and survives API throttling: when a step is rate limited (HTTP 429 / quota
exhaustion) it writes `.project/checkpoint.json` and exits 75 (EX_TEMPFAIL). `--resume` reloads that checkpoint,
skips the steps that already completed, waits out Retry-After and continues.

  python3 tools/orchestrator.py --plan plan.json
  python3 tools/orchestrator.py --resume [--no-wait] [--allow-head-change]

Plan file: {"context": {...}, "steps": [{"id": "build", "argv": ["npm", "run", "build"], "timeout": 600}]}

Design notes
  * Steps are argv lists run without a shell; there is no network access and no credential handling in here.
  * The checkpoint stores progress and a bounded *evidence* snapshot of the working tree (branch, HEAD, changed
    paths, redacted diff). The diff is never re-applied on resume; resume only refuses to continue if HEAD moved
    (override with --allow-head-change) and warns if the set of changed files differs.
  * Secrets: secret-looking files are excluded from the diff, key/token/password/Authorization values are redacted
    from the diff and from the failing step's output tail, and the file is written 0600 via an atomic replace.
    `.project/checkpoint.json` is gitignored.
  * Exit codes: 0 done, 1 step failed, 2 usage / invalid or unsafe checkpoint, 75 rate limited (checkpoint written
    or resume not yet allowed).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_CHECKPOINT = ROOT / ".project" / "checkpoint.json"
CHECKPOINT_VERSION = 1
EXIT_OK, EXIT_FAILED, EXIT_USAGE, EXIT_RATE_LIMITED = 0, 1, 2, 75
MAX_RETRY_AFTER = 3600.0
MAX_DIFF_BYTES = 200_000
MAX_OUTPUT_TAIL = 4_000
MAX_STEPS = 1_000
MAX_CONTEXT_BYTES = 64_000
DEFAULT_STEP_TIMEOUT = 3_600
STATES = {"running", "checkpointed", "failed"}

# Deliberately strict: a bare "rate limit" or a bare number 429 is not enough (this repository has rate-limit *tests*
# whose failures must not be mistaken for throttling). Only evaluated when a step exits non-zero.
_RATE_LIMIT = re.compile(
    r"(?i)too many requests|rate[ _-]?limit(?:ed|\s+(?:exceeded|reached|hit))|quota[ _]?(?:exceeded|limit exceeded)|"
    r"resource_exhausted|"
    # a 429 only counts with an HTTP/status/code context: `line 429` or `expected 429, got 200` are ordinary failures
    r"\bhttp(?:/\d(?:\.\d)?)?\s*:?\s*429(?!\d)|\bstatus(?:[ _-]?code)?[\"']?\s*[:=]?\s*429(?!\d)|"
    r"\bcode[\"']?\s*[:=]?\s*429(?!\d)")
_RETRY_AFTER = re.compile(r"(?i)retry[-_ ]?after[\"']?\s*[:=]\s*(\d+(?:\.\d+)?)")
_VALUE = r"(?:\"[^\"\n]*\"|'[^'\n]*'|\S+)"
_REDACTIONS = [
    # the whole Authorization value (scheme + credentials), quoted or not
    (re.compile(r"(?i)([\"']?authorization[\"']?\s*[:=]\s*)(?:\"[^\"\n]*\"|'[^'\n]*'|[^\r\n]+)"), r"\1[REDACTED]"),
    (re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"), "Bearer [REDACTED]"),
    # key names may be quoted and may carry prefixes/suffixes (GITHUB_TOKEN, "client_secret", AWS_SECRET_ACCESS_KEY)
    (re.compile(r"(?i)((?<![\w.-])[\"']?[\w.-]{0,40}?(?:api[_-]?key|access[_-]?key|private[_-]?key|token|secret|password|passwd)[\w.-]{0,40}[\"']?"
                r"\s*[:=]\s*)" + _VALUE), r"\1[REDACTED]"),
]
_DIFF_EXCLUDES = [":(exclude)*.env", ":(exclude)*.env.*", ":(exclude)*.pem", ":(exclude)*.key", ":(exclude)*.p12",
                  ":(exclude)*.keystore", ":(exclude)*secret*", ":(exclude)*credential*"]
_STEP_ID = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")


class PlanError(ValueError):
    pass


class CheckpointError(ValueError):
    pass


class RateLimited(Exception):
    """Raised by an in-process runner to signal throttling (HTTP 429 / quota)."""

    def __init__(self, retry_after: float | None = None):
        super().__init__("rate limited")
        self.retry_after = retry_after


def detect_rate_limit(returncode: int, output: str) -> tuple[bool, float | None]:
    """Classify a finished command. Success is never throttling."""
    if returncode == 0 or not _RATE_LIMIT.search(output or ""):
        return False, None
    match = _RETRY_AFTER.search(output)
    return True, (min(float(match.group(1)), MAX_RETRY_AFTER) if match else None)


def redact(text: str) -> str:
    for pattern, replacement in _REDACTIONS:
        text = pattern.sub(replacement, text)
    return text


_SECRET_FLAG = re.compile(r"(?i)^--?[\w-]*(?:api[_-]?key|access[_-]?key|token|secret|password|passwd|authorization)[\w-]*$")


def _credential_in_text(text: str) -> bool:
    return redact(text) != text


def _credential_in_context(value: object, key: str = "") -> bool:
    """True when any string leaf of the context looks like a credential, judged by its own key name and content."""
    if isinstance(value, dict):
        return any(_credential_in_context(v, str(k)) for k, v in value.items())
    if isinstance(value, list):
        return any(_credential_in_context(v, key) for v in value)
    if isinstance(value, str) and value:
        return _credential_in_text(json.dumps({key: value})) or _credential_in_text(value)
    return False


def validate_plan(plan: object) -> dict:
    if not isinstance(plan, dict) or not isinstance(plan.get("steps"), list) or not plan["steps"]:
        raise PlanError("plan must be an object with a non-empty 'steps' list")
    if len(plan["steps"]) > MAX_STEPS:
        raise PlanError(f"plan has more than {MAX_STEPS} steps")
    context = plan.get("context", {})
    if not isinstance(context, dict) or len(json.dumps(context)) > MAX_CONTEXT_BYTES:
        raise PlanError("context must be a JSON object under 64 KB")
    if _credential_in_context(context):
        raise PlanError("context appears to contain a credential; the plan is persisted in the checkpoint, so pass "
                        "secrets through the environment of the process that runs the orchestrator instead")
    seen, steps = set(), []
    for step in plan["steps"]:
        if not isinstance(step, dict) or set(step) - {"id", "argv", "timeout"}:
            raise PlanError("each step must be an object with only id, argv and optional timeout")
        sid, argv = step.get("id"), step.get("argv")
        if not isinstance(sid, str) or not _STEP_ID.match(sid):
            raise PlanError(f"invalid step id: {sid!r}")
        if sid in seen:
            raise PlanError(f"duplicate step id: {sid}")
        if (not isinstance(argv, list) or not argv or any(not isinstance(a, str) or not a or len(a) > 4096 for a in argv)):
            raise PlanError(f"step {sid}: argv must be a non-empty list of strings (no shell strings)")
        if any(_credential_in_text(a) or (i and _SECRET_FLAG.match(argv[i - 1]) and "=" not in argv[i - 1])
               for i, a in enumerate(argv)):
            raise PlanError(f"step {sid}: argv appears to contain a credential; the plan is persisted in the "
                            "checkpoint, so supply secrets through the environment, not command arguments")
        timeout = step.get("timeout", DEFAULT_STEP_TIMEOUT)
        if not isinstance(timeout, int) or isinstance(timeout, bool) or not 1 <= timeout <= 86_400:
            raise PlanError(f"step {sid}: timeout must be an integer 1..86400")
        seen.add(sid)
        steps.append({"id": sid, "argv": list(argv), "timeout": timeout})
    return {"context": context, "steps": steps}


def _canonical(payload: dict) -> bytes:
    return json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()


def _git(root: pathlib.Path, *args: str) -> tuple[int, str]:
    try:
        done = subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, errors="replace", timeout=60,
                              env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
        return done.returncode, done.stdout
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def git_snapshot(root: pathlib.Path, ignore: str | None = None) -> dict:
    """`ignore` (repo-relative) keeps the checkpoint file and its temp files out of their own change list."""
    rc, head = _git(root, "rev-parse", "HEAD")
    if rc != 0:
        return {"available": False}
    _, branch = _git(root, "rev-parse", "--abbrev-ref", "HEAD")
    _, status = _git(root, "status", "--porcelain=v1", "--untracked-files=all")
    pending = []
    for line in status.splitlines():
        path = line[3:].split(" -> ")[-1].strip().strip('"')
        if path and path != ignore and not pathlib.PurePosixPath(path).name.startswith(".checkpoint-"):
            pending.append(path)
    _, diff = _git(root, "diff", "HEAD", "--no-color", "--no-ext-diff", "--", ".", *_DIFF_EXCLUDES)
    diff = redact(diff)
    encoded = diff.encode()
    truncated = len(encoded) > MAX_DIFF_BYTES
    if truncated:
        diff = encoded[:MAX_DIFF_BYTES].decode(errors="ignore")
    return {"available": True, "branch": branch.strip(), "head": head.strip(), "pending_edits": sorted(set(pending)),
            "diff": diff, "diff_truncated": truncated, "diff_sha256": hashlib.sha256(encoded).hexdigest()}


def write_atomic(path: pathlib.Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    body = {**payload, "integrity": {"sha256": hashlib.sha256(_canonical(payload)).hexdigest()}}
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".checkpoint-", suffix=".tmp")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as handle:
            handle.write(json.dumps(body, indent=2, sort_keys=True))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    except BaseException:
        pathlib.Path(tmp).unlink(missing_ok=True)
        raise


def load_checkpoint(path: pathlib.Path) -> dict:
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise CheckpointError(f"cannot read checkpoint: {error}") from error
    if not isinstance(data, dict) or not isinstance(data.get("integrity"), dict):
        raise CheckpointError("checkpoint is malformed")
    claimed = data["integrity"].get("sha256")
    payload = {k: v for k, v in data.items() if k != "integrity"}
    if claimed != hashlib.sha256(_canonical(payload)).hexdigest():
        raise CheckpointError("checkpoint integrity check failed (modified or corrupt)")
    if data.get("version") != CHECKPOINT_VERSION or data.get("state") not in STATES:
        raise CheckpointError("unsupported checkpoint version or state")
    try:
        data["plan"] = validate_plan(data.get("plan"))
    except PlanError as error:
        raise CheckpointError(f"checkpoint plan invalid: {error}") from error
    ids = [s["id"] for s in data["plan"]["steps"]]
    progress = data.get("progress")
    if (not isinstance(progress, dict) or not isinstance(progress.get("completed"), list)
            or any(c not in ids for c in progress["completed"]) or progress.get("pending") not in ids + [None]):
        raise CheckpointError("checkpoint progress does not match its plan")
    return data


class Orchestrator:
    def __init__(self, root=ROOT, checkpoint=DEFAULT_CHECKPOINT, runner=None, sleep=time.sleep, now=time.time, log=None):
        self.root = pathlib.Path(root)
        self.checkpoint = pathlib.Path(checkpoint)
        self.runner = runner or self._subprocess_runner
        self.sleep, self.now = sleep, now
        self.log = log or (lambda message: print(f"[orchestrator] {message}", file=sys.stderr))

    def _subprocess_runner(self, step: dict) -> tuple[int, str]:
        posix = os.name == "posix"
        try:
            proc = subprocess.Popen(step["argv"], cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    text=True, errors="replace", start_new_session=posix)
        except OSError as error:
            return 127, f"cannot start command: {error}"
        try:
            out, err = proc.communicate(timeout=step.get("timeout", DEFAULT_STEP_TIMEOUT))
            return proc.returncode, (out or "") + (err or "")
        except subprocess.TimeoutExpired:
            self._terminate_tree(proc, posix)
            return 124, f"step timed out after {step.get('timeout')}s"

    @staticmethod
    def _terminate_tree(proc: subprocess.Popen, posix: bool) -> None:
        """Kill the step's whole process group and reap it, so a timed-out step cannot keep running (and keep
        modifying files) while its checkpoint is already resumable."""
        if posix:
            for sig, grace in ((signal.SIGTERM, 3), (signal.SIGKILL, 0)):
                try:
                    os.killpg(proc.pid, sig)
                except ProcessLookupError:
                    break
                if grace:
                    try:
                        proc.wait(timeout=grace)
                    except subprocess.TimeoutExpired:
                        pass
        else:
            proc.kill()
        try:
            proc.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            for stream in (proc.stdout, proc.stderr):
                if stream:
                    stream.close()

    def _own_path(self) -> str | None:
        try:
            return self.checkpoint.resolve().relative_to(self.root.resolve()).as_posix()
        except ValueError:
            return None

    def _save(self, plan, completed, pending, state, reason=None, retry_after=None, tail=""):
        created = self.now()
        write_atomic(self.checkpoint, {
            "version": CHECKPOINT_VERSION, "state": state, "reason": reason,
            "created_at": datetime.fromtimestamp(created, timezone.utc).isoformat(),
            "retry_after_seconds": retry_after,
            "resume_not_before": (created + retry_after) if retry_after else None,
            "plan": plan, "progress": {"completed": list(completed), "pending": pending},
            "last_output_tail": redact(tail)[-MAX_OUTPUT_TAIL:], "git": git_snapshot(self.root, self._own_path())})

    def _execute(self, plan: dict, completed: list[str]) -> int:
        for step in plan["steps"]:
            if step["id"] in completed:
                continue
            self.log(f"step {step['id']}")
            try:
                code, output = self.runner(step)
            except RateLimited as limited:
                return self._rate_limited(plan, completed, step["id"], limited.retry_after, str(limited))
            if code == 0:
                completed.append(step["id"])
                self._save(plan, completed, None, "running")      # crash-safe progress
                continue
            throttled, retry_after = detect_rate_limit(code, output)
            if throttled:
                return self._rate_limited(plan, completed, step["id"], retry_after, output)
            self._save(plan, completed, step["id"], "failed", reason=f"step {step['id']} exited {code}", tail=output)
            self.log(f"step {step['id']} failed (exit {code}); checkpoint kept for diagnosis")
            return EXIT_FAILED
        self.checkpoint.unlink(missing_ok=True)
        self.log("all steps complete")
        return EXIT_OK

    def _rate_limited(self, plan, completed, pending, retry_after, tail) -> int:
        self._save(plan, completed, pending, "checkpointed", reason="rate_limited", retry_after=retry_after, tail=tail)
        self.log(f"rate limited at step {pending}; checkpoint written to {self.checkpoint}; resume with --resume")
        return EXIT_RATE_LIMITED

    def run(self, plan: dict) -> int:
        return self._execute(validate_plan(plan), [])

    def resume(self, wait: bool = True, allow_head_change: bool = False) -> int:
        if not self.checkpoint.exists():
            self.log("no checkpoint to resume")
            return EXIT_USAGE
        try:
            data = load_checkpoint(self.checkpoint)
        except CheckpointError as error:
            self.log(f"refusing to resume: {error}")
            return EXIT_USAGE
        saved = data.get("git", {})
        if saved.get("available"):
            current = git_snapshot(self.root, self._own_path())
            if current.get("head") != saved.get("head") and not allow_head_change:
                self.log(f"refusing to resume: HEAD moved {saved.get('head', '')[:8]} -> {current.get('head', '')[:8]}"
                         " (use --allow-head-change after reviewing)")
                return EXIT_USAGE
            if current.get("pending_edits") != saved.get("pending_edits"):
                self.log("warning: the set of changed files differs from the checkpoint")
        not_before = data.get("resume_not_before")
        remaining = max(0.0, not_before - self.now()) if not_before else 0.0
        if remaining > 0:
            if not wait:
                self.log(f"too early to resume: {remaining:.0f}s of Retry-After remain")
                return EXIT_RATE_LIMITED
            self.log(f"waiting {remaining:.0f}s for Retry-After")
            self.sleep(remaining)
        return self._execute(data["plan"], list(data["progress"]["completed"]))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--plan", type=pathlib.Path, help="JSON plan file to run")
    group.add_argument("--resume", action="store_true", help="continue from the checkpoint")
    parser.add_argument("--checkpoint", type=pathlib.Path, default=DEFAULT_CHECKPOINT)
    parser.add_argument("--root", type=pathlib.Path, default=ROOT)
    parser.add_argument("--no-wait", action="store_true", help="do not sleep for Retry-After; exit 75 if too early")
    parser.add_argument("--allow-head-change", action="store_true")
    args = parser.parse_args(argv)
    orchestrator = Orchestrator(root=args.root, checkpoint=args.checkpoint)
    if args.resume:
        return orchestrator.resume(wait=not args.no_wait, allow_head_change=args.allow_head_change)
    try:
        return orchestrator.run(json.loads(args.plan.read_text()))
    except (OSError, ValueError) as error:
        print(f"[orchestrator] invalid plan: {error}", file=sys.stderr)
        return EXIT_USAGE


if __name__ == "__main__":
    sys.exit(main())
