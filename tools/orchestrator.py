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
import codecs
import contextlib
import hashlib
import json
import os
import pathlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone

try:
    import fcntl
except ImportError:                                         # pragma: no cover (Windows)
    fcntl = None

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_CHECKPOINT = ROOT / ".project" / "checkpoint.json"
CHECKPOINT_VERSION = 1
EXIT_OK, EXIT_FAILED, EXIT_USAGE, EXIT_RATE_LIMITED = 0, 1, 2, 75
MAX_RETRY_AFTER = 3600.0
MAX_DIFF_BYTES = 200_000
MAX_OUTPUT_TAIL = 4_000
MAX_CAPTURE = 64 * 1024            # per stream, kept in memory while a step runs
_SCAN_OVERLAP = 512               # chars kept between chunks so a signal split across reads is still seen
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
    # gameplay identifiers must not reach diagnostics (AGENTS.md privacy rule): playerId, request_id, inventoryId, ...
    (re.compile(r"(?i)((?<![\w.-])[\"']?[\w.-]{0,40}?(?:player|request|inventory|user|account|session|character|guild|ship)"
                r"[_-]?id[\w.-]{0,20}[\"']?\s*[:=]\s*)" + _VALUE), r"\1[REDACTED]"),
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


class _BoundedCapture:
    """Drains one pipe incrementally: keeps only the last MAX_CAPTURE chars, but remembers (separately) the first
    rate-limit signal and Retry-After it saw, so a step cannot exhaust memory nor push its own 429 out of view."""

    def __init__(self, limit: int = MAX_CAPTURE):
        self.limit, self.tail, self.signal, self.retry = limit, "", None, None
        self._carry = ""
        self._decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")

    def feed(self, data: bytes, final: bool = False) -> None:
        text = self._decoder.decode(data, final)
        window = self._carry + text
        # A match that touches the end of the window may still be growing ("Retry-After: 1" + "20", "429" + "5"):
        # keep it in the carry and decide on the next read, or at EOF.
        if self.signal is None:
            match = _RATE_LIMIT.search(window)
            if match and (final or match.end() < len(window)):
                self.signal = match.group(0)
        if self.retry is None:
            match = _RETRY_AFTER.search(window)
            if match and (final or match.end() < len(window)):
                self.retry = match.group(0)
        self._carry = window[-_SCAN_OVERLAP:]
        self.tail = (self.tail + text)[-self.limit:]

    def drain(self, stream) -> None:
        try:
            while True:
                chunk = stream.read1(65536) if hasattr(stream, "read1") else stream.read(65536)
                if not chunk:
                    break
                self.feed(chunk)
            self.feed(b"", final=True)
        except (OSError, ValueError):                 # stream closed underneath us after the step was killed
            pass

    def text(self) -> str:
        kept = "".join(f"[captured] {item}\n" for item in (self.signal, self.retry) if item and item not in self.tail)
        return kept + self.tail


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


# Variables git (or its helpers) legitimately need. Everything else is dropped so ambient GIT_DIR / GIT_WORK_TREE /
# GIT_INDEX_FILE / GIT_EXTERNAL_DIFF / GIT_CONFIG_* cannot redirect or script the snapshot, and secrets never reach it.
_GIT_ENV_ALLOW = ("PATH", "HOME", "USERPROFILE", "TMPDIR", "TEMP", "TMP", "SYSTEMROOT", "LANG", "LC_ALL", "LC_CTYPE")


def _resolve_git(root: pathlib.Path) -> str | None:
    """Absolute path of `git`, searching only PATH entries that are absolute and outside the repository, so a `git`
    planted in the working tree (or reached through a relative PATH entry such as ".") is never executed."""
    try:
        repo = root.resolve()
    except OSError:
        return None
    safe = []
    for entry in os.environ.get("PATH", "").split(os.pathsep):
        if not entry or not os.path.isabs(entry):
            continue
        try:
            resolved = pathlib.Path(entry).resolve()
        except OSError:
            continue
        if resolved == repo or repo in resolved.parents:
            continue
        safe.append(entry)
    found = shutil.which("git", path=os.pathsep.join(safe))
    return found if found and os.path.isabs(found) else None


def _git(root: pathlib.Path, *args: str, errors: str = "replace") -> tuple[int, str]:
    git = _resolve_git(root)
    if git is None:
        return 127, ""
    env = {name: os.environ[name] for name in _GIT_ENV_ALLOW if name in os.environ}
    env["GIT_TERMINAL_PROMPT"] = "0"
    try:
        done = subprocess.run([git, *args], cwd=root, capture_output=True, text=True, errors=errors, timeout=60, env=env)
        return done.returncode, done.stdout
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def _hash_stream(digest, handle) -> None:
    while block := handle.read(1 << 20):
        digest.update(block)


def _content_fingerprint(root: pathlib.Path, paths: list[str]) -> str:
    """Digest of the actual bytes of every changed or untracked file (not just its name), so resume can tell that an
    input changed even when HEAD and the set of paths are identical. Streamed, so it is not capped like the diff."""
    digest = hashlib.sha256()
    for rel in sorted(set(paths)):
        path = root / rel
        digest.update(os.fsencode(rel) + b"\0")
        try:
            if path.is_symlink():
                digest.update(b"link:" + os.fsencode(os.readlink(path)))
            elif path.is_file():
                with path.open("rb") as handle:
                    _hash_stream(digest, handle)
            else:
                digest.update(b"absent-or-directory")
        except OSError as error:
            digest.update(f"unreadable:{error.errno}".encode())
        digest.update(b"\0")
    return digest.hexdigest()


def git_snapshot(root: pathlib.Path, ignore: str | None = None) -> dict:
    """`ignore` (repo-relative) keeps the checkpoint file and its temp files out of their own change list."""
    rc, head = _git(root, "rev-parse", "HEAD")
    if rc != 0:
        return {"available": False}
    _, branch = _git(root, "rev-parse", "--abbrev-ref", "HEAD")
    # -z: NUL-terminated and unquoted, so names with non-ASCII bytes, tabs or quotes are real paths we can hash.
    # surrogateescape keeps non-UTF-8 names round-trippable to the filesystem.
    _, status = _git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all", errors="surrogateescape")
    pending = []
    entries = status.split("\0")
    index = 0
    while index < len(entries):
        entry = entries[index]
        index += 1
        if len(entry) < 4:
            continue
        path = entry[3:]
        if entry[0] in "RC":                      # rename/copy: "XY new" is followed by the old name as its own entry
            index += 1
        if path != ignore and not pathlib.PurePosixPath(path).name.startswith(".checkpoint-"):
            pending.append(path)
    _, diff = _git(root, "diff", "HEAD", "--no-color", "--no-ext-diff", "--", ".", *_DIFF_EXCLUDES)
    diff = redact(diff)
    encoded = diff.encode()
    truncated = len(encoded) > MAX_DIFF_BYTES
    if truncated:
        diff = encoded[:MAX_DIFF_BYTES].decode(errors="ignore")
    return {"available": True, "branch": branch.strip(), "head": head.strip(), "pending_edits": sorted(set(pending)),
            "diff": diff, "diff_truncated": truncated, "diff_sha256": hashlib.sha256(encoded).hexdigest(),
            "content_sha256": _content_fingerprint(root, pending)}


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
                                    start_new_session=posix)
        except OSError as error:
            return 127, f"cannot start command: {error}"
        captures = (_BoundedCapture(), _BoundedCapture())
        readers = [threading.Thread(target=cap.drain, args=(stream,), daemon=True)
                   for cap, stream in zip(captures, (proc.stdout, proc.stderr))]
        for reader in readers:
            reader.start()

        def finish():
            for reader in readers:
                reader.join(timeout=5)               # a surviving descendant may still hold the pipe open
            for stream in (proc.stdout, proc.stderr):
                with contextlib.suppress(OSError, ValueError):
                    stream.close()
            return "".join(cap.text() for cap in captures)
        try:
            proc.wait(timeout=step.get("timeout", DEFAULT_STEP_TIMEOUT))
            if posix:
                self._kill_group(proc.pid)        # a step must not leave background children mutating files
            return proc.returncode, finish()
        except subprocess.TimeoutExpired:
            self._terminate_tree(proc, posix)
            finish()
            return 124, f"step timed out after {step.get('timeout')}s"
        except BaseException:
            # Ctrl-C / SIGTERM-driven exit: the step runs in its own session, so it would otherwise outlive us and
            # keep mutating files while a later --resume starts the same step again.
            self._terminate_tree(proc, posix)
            finish()
            raise

    @staticmethod
    def _kill_group(pgid: int, grace: float = 0.3) -> None:
        """SIGTERM the process group, give it `grace` seconds, then SIGKILL whatever is left. No-op if it is empty."""
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(pgid, sig)
            except (ProcessLookupError, PermissionError):
                return
            deadline = time.monotonic() + (grace if sig == signal.SIGTERM else 0.5)
            while time.monotonic() < deadline:
                try:
                    os.killpg(pgid, 0)
                except (ProcessLookupError, PermissionError):
                    return
                time.sleep(0.02)

    @staticmethod
    def _terminate_tree(proc: subprocess.Popen, posix: bool) -> None:
        """Kill the step's whole process group and reap it, so a timed-out or interrupted step cannot keep running
        (and keep modifying files) while its checkpoint is already resumable."""
        if posix:
            Orchestrator._kill_group(proc.pid, grace=1.0)
        else:
            proc.kill()
        with contextlib.suppress(subprocess.TimeoutExpired):
            proc.wait(timeout=10)

    @contextlib.contextmanager
    def _exclusive(self):
        """Process-lifetime exclusive lock for a run or resume. Yields False if another live executor owns the
        checkpoint. flock is released by the OS when the holder dies, so a crash never leaves a stale lock; the file's
        `.checkpoint-` prefix keeps it out of the input fingerprint."""
        if fcntl is None:                                   # non-POSIX: no advisory lock available
            self.log("warning: no file locking on this platform; do not run two orchestrators on one checkpoint")
            yield True
            return
        self.checkpoint.parent.mkdir(parents=True, exist_ok=True)
        handle = open(self.checkpoint.parent / f".checkpoint-{self.checkpoint.name}.lock", "a")
        try:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                self.log("refusing to start: another orchestrator is already executing against this checkpoint")
                yield False
                return
            yield True
        finally:
            handle.close()                                  # also drops the lock

    def _own_path(self) -> str | None:
        try:
            return self.checkpoint.resolve().relative_to(self.root.resolve()).as_posix()
        except ValueError:
            return None

    def _inputs_fingerprint(self) -> str | None:
        snap = git_snapshot(self.root, self._own_path())
        return snap.get("content_sha256") if snap.get("available") else None

    def _save(self, plan, completed, pending, state, reason=None, retry_after=None, tail=""):
        created = self.now()
        git = git_snapshot(self.root, self._own_path())
        baseline = getattr(self, "_input_baseline", None)
        if state in ("failed", "checkpointed") and completed and baseline and git.get("available"):
            # Completed steps were validated against the inputs as they stood at the last step boundary. If the step
            # that just failed or was throttled edited them, record the validated baseline so --resume sees the drift.
            git["content_sha256"] = baseline
        write_atomic(self.checkpoint, {
            "version": CHECKPOINT_VERSION, "state": state, "reason": reason,
            "created_at": datetime.fromtimestamp(created, timezone.utc).isoformat(),
            "retry_after_seconds": retry_after,
            "resume_not_before": (created + retry_after) if retry_after else None,
            "plan": plan, "progress": {"completed": list(completed), "pending": pending},
            "last_output_tail": redact(tail)[-MAX_OUTPUT_TAIL:], "git": git})

    def _head(self) -> str | None:
        rc, head = _git(self.root, "rev-parse", "HEAD")
        return head.strip() if rc == 0 else None

    def _head_moved(self, plan: dict, completed: list[str], baseline: str | None, step_id: str) -> bool:
        """Steps are evidence for the commit they ran on. If a step moved HEAD, nothing completed so far (nor the step
        that moved it) can be reused: invalidate all progress and stop so the next run starts from the new commit."""
        if baseline is None or self._head() == baseline:
            return False
        completed.clear()
        self._save(plan, completed, step_id, "failed",
                   reason=f"HEAD moved during step {step_id}; completed steps were invalidated")
        self.log(f"HEAD moved during step {step_id}; discarded all completed steps. Re-run (--resume) on the new commit")
        return True

    def _execute(self, plan: dict, completed: list[str]) -> int:
        baseline = self._head()
        self._input_baseline = self._inputs_fingerprint()
        for step in plan["steps"]:
            if step["id"] in completed:
                continue
            self.log(f"step {step['id']}")
            try:
                code, output = self.runner(step)
            except RateLimited as limited:
                if self._head_moved(plan, completed, baseline, step["id"]):
                    return EXIT_FAILED
                return self._rate_limited(plan, completed, step["id"], limited.retry_after, str(limited))
            if self._head_moved(plan, completed, baseline, step["id"]):
                return EXIT_FAILED
            if code == 0:
                completed.append(step["id"])
                self._input_baseline = self._inputs_fingerprint()
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
        plan = validate_plan(plan)
        with self._exclusive() as acquired:
            return self._execute(plan, []) if acquired else EXIT_USAGE

    def _check_unchanged(self, saved: dict, data: dict, allow_head_change: bool, allow_input_change: bool):
        """Refuse (EXIT_USAGE) when HEAD or input content moved since the checkpoint; with the input override, drop the
        completed steps so everything re-runs on the current files. Returns None when it is safe to continue."""
        if not saved.get("available"):
            return None
        current = git_snapshot(self.root, self._own_path())
        if current.get("head") != saved.get("head"):
            if not allow_head_change:
                self.log(f"refusing to resume: HEAD moved {saved.get('head', '')[:8]} -> {current.get('head', '')[:8]}"
                         " (use --allow-head-change after reviewing)")
                return EXIT_USAGE
            # Evidence is bound to the exact commit: steps that passed on the old HEAD say nothing about the new one.
            self.log("HEAD moved since the checkpoint; discarding completed steps and re-running all of them")
            data["progress"]["completed"] = []
        if current.get("pending_edits") != saved.get("pending_edits"):
            self.log("warning: the set of changed files differs from the checkpoint")
        if current.get("content_sha256") != saved.get("content_sha256"):
            if not allow_input_change:
                self.log("refusing to resume: the content of modified or untracked files changed since the "
                         "checkpoint, so completed steps were validated against different input "
                         "(use --allow-input-change to re-run every step on the current files)")
                return EXIT_USAGE
            self.log("inputs changed since the checkpoint; discarding completed steps and re-running all of them")
            data["progress"]["completed"] = []
        return None

    def resume(self, wait: bool = True, allow_head_change: bool = False, allow_input_change: bool = False) -> int:
        with self._exclusive() as acquired:
            if not acquired:
                return EXIT_USAGE
            return self._resume_locked(wait, allow_head_change, allow_input_change)

    def _resume_locked(self, wait: bool, allow_head_change: bool, allow_input_change: bool) -> int:
        if not self.checkpoint.exists():
            self.log("no checkpoint to resume")
            return EXIT_USAGE
        try:
            data = load_checkpoint(self.checkpoint)
        except CheckpointError as error:
            self.log(f"refusing to resume: {error}")
            return EXIT_USAGE
        saved = data.get("git", {})
        refusal = self._check_unchanged(saved, data, allow_head_change, allow_input_change)
        if refusal is not None:
            return refusal
        not_before = data.get("resume_not_before")
        remaining = max(0.0, not_before - self.now()) if not_before else 0.0
        if remaining > 0:
            if not wait:
                self.log(f"too early to resume: {remaining:.0f}s of Retry-After remain")
                return EXIT_RATE_LIMITED
            self.log(f"waiting {remaining:.0f}s for Retry-After")
            self.sleep(remaining)
            # Retry-After can last up to an hour: HEAD and inputs may have changed while we slept, so re-verify
            # immediately before reusing the completed steps.
            refusal = self._check_unchanged(saved, data, allow_head_change, allow_input_change)
            if refusal is not None:
                return refusal
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
    parser.add_argument("--allow-input-change", action="store_true",
                        help="re-run every step if modified/untracked file content changed since the checkpoint")
    args = parser.parse_args(argv)
    orchestrator = Orchestrator(root=args.root, checkpoint=args.checkpoint)
    # Python's default SIGTERM action ends the process without unwinding, which would orphan the step's isolated
    # process group. Turn it into SystemExit so the runner's cleanup (and any `finally`) runs first.
    if hasattr(signal, "SIGTERM"):
        def _terminate(signum, _frame):
            raise SystemExit(128 + signum)
        signal.signal(signal.SIGTERM, _terminate)
    if args.resume:
        return orchestrator.resume(wait=not args.no_wait, allow_head_change=args.allow_head_change,
                                   allow_input_change=args.allow_input_change)
    try:
        return orchestrator.run(json.loads(args.plan.read_text()))
    except (OSError, ValueError) as error:
        print(f"[orchestrator] invalid plan: {error}", file=sys.stderr)
        return EXIT_USAGE


if __name__ == "__main__":
    sys.exit(main())
