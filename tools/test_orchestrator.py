import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import orchestrator as orch


def git(cwd, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@example.invalid", *args], cwd=cwd, check=True,
                   capture_output=True, text=True)


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self._tmp.name)
        git(self.root, "init", "-q")
        (self.root / "a.txt").write_text("one\n")
        git(self.root, "add", "a.txt")
        git(self.root, "commit", "-q", "-m", "init")
        self.ckpt = self.root / ".project" / "checkpoint.json"
        self.calls = []

    def tearDown(self):
        self._tmp.cleanup()

    def plan(self, ids=("s1", "s2", "s3"), context=None):
        return {"context": context or {"task": "demo"}, "steps": [{"id": i, "argv": ["true"]} for i in ids]}

    def make(self, behaviour=None, sleep=None, now=None):
        behaviour = behaviour or {}

        def runner(step):
            self.calls.append(step["id"])
            outcome = behaviour.get(step["id"])
            if callable(outcome):
                outcome = outcome()
            if isinstance(outcome, Exception):
                raise outcome
            return outcome or (0, "ok")
        return orch.Orchestrator(root=self.root, checkpoint=self.ckpt, runner=runner,
                                 sleep=sleep or (lambda s: self.calls.append(("sleep", s))), now=now or orch.time.time)


class Detection(unittest.TestCase):
    def test_detects_rate_limit_signals(self):
        for text in ["HTTP 429 Too Many Requests", "Error: rate limit exceeded", "rate-limited by upstream",
                     "quota exceeded for project", "RESOURCE_EXHAUSTED: quota", "status: 429"]:
            self.assertTrue(orch.detect_rate_limit(1, text)[0], text)

    def test_ignores_other_failures_and_lookalike_numbers(self):
        for text in ["AssertionError: boom", "listening on port 14290", "build id 4291 failed", ""]:
            self.assertFalse(orch.detect_rate_limit(1, text)[0], text)


    def test_a_bare_429_is_not_throttling(self):
        for text in ["AssertionError: expected 429, got 200", 'File "x.py", line 429, in <module>', "429", "processed 429 rows",
                     "assert status == 429"]:
            self.assertFalse(orch.detect_rate_limit(1, text)[0], text)

    def test_429_with_http_or_status_context_is_throttling(self):
        for text in ["HTTP/1.1 429", "HTTP 429", "status code 429", "Status: 429", 'status=429', '{"error": {"code": 429}}',
                     "429 Too Many Requests", "received error code 429 from api"]:
            self.assertTrue(orch.detect_rate_limit(1, text)[0], text)

    def test_success_is_never_a_rate_limit(self):
        self.assertFalse(orch.detect_rate_limit(0, "HTTP 429 mentioned in a log line")[0])

    def test_parses_retry_after_seconds_and_caps_it(self):
        self.assertEqual(orch.detect_rate_limit(1, "429 Too Many Requests\nRetry-After: 42"), (True, 42.0))
        self.assertEqual(orch.detect_rate_limit(1, "HTTP 429 retry-after=999999")[1], orch.MAX_RETRY_AFTER)
        self.assertEqual(orch.detect_rate_limit(1, "HTTP 429"), (True, None))


class Plan(Base):
    def test_rejects_duplicate_ids_empty_plans_and_shell_strings(self):
        for bad in [{"steps": []}, self.plan(("a", "a")), {"steps": [{"id": "x", "argv": "echo hi"}]},
                    {"steps": [{"id": "bad id!", "argv": ["true"]}]}, {"steps": [{"id": "x", "argv": []}]}]:
            with self.assertRaises(orch.PlanError):
                orch.validate_plan(bad)


class PlanCredentials(Base):
    """Codex P2: the plan is serialised into the checkpoint, so credential-bearing plan data must be refused."""

    def _plan(self, argv=None, context=None):
        return {"context": context or {}, "steps": [{"id": "s1", "argv": argv or ["true"]}]}

    def test_credentials_in_argv_are_rejected(self):
        for argv in (["curl", "-H", "Authorization: Bearer abc123"], ["tool", "--token", "abc123"],
                     ["tool", "--api-key=abc123"], ["tool", "password=hunter2"]):
            with self.assertRaises(orch.PlanError, msg=str(argv)):
                orch.validate_plan(self._plan(argv=argv))

    def test_credentials_in_context_are_rejected(self):
        for ctx in ({"api_key": "abc123"}, {"nested": {"client_secret": "x1"}}, {"h": ["Authorization: Bearer zzz"]}):
            with self.assertRaises(orch.PlanError, msg=str(ctx)):
                orch.validate_plan(self._plan(context=ctx))

    def test_ordinary_plans_still_validate(self):
        orch.validate_plan(self._plan(argv=["python3", "-m", "unittest", "--verbose"], context={"ticket": "IOM-00", "tokens_budget": 5}))


class RunAndResume(Base):
    def test_runs_all_steps_and_leaves_no_checkpoint(self):
        self.assertEqual(self.make().run(self.plan()), orch.EXIT_OK)
        self.assertEqual(self.calls, ["s1", "s2", "s3"])
        self.assertFalse(self.ckpt.exists())

    def test_rate_limit_writes_a_checkpoint_and_exits_75(self):
        o = self.make({"s2": orch.RateLimited(30)})
        (self.root / "a.txt").write_text("one\ntwo\n")          # a pending edit
        (self.root / "new.txt").write_text("untracked\n")
        self.assertEqual(o.run(self.plan(context={"task": "demo", "n": 1})), orch.EXIT_RATE_LIMITED)
        data = json.loads(self.ckpt.read_text())
        self.assertEqual(data["state"], "checkpointed")
        self.assertEqual(data["progress"]["completed"], ["s1"])
        self.assertEqual(data["progress"]["pending"], "s2")
        self.assertEqual(data["plan"]["context"], {"task": "demo", "n": 1})
        self.assertEqual(data["retry_after_seconds"], 30)
        self.assertIn("a.txt", data["git"]["pending_edits"])
        self.assertIn("new.txt", data["git"]["pending_edits"])
        self.assertIn("+two", data["git"]["diff"])
        self.assertNotIn(".project/checkpoint.json", data["git"]["pending_edits"])   # never lists its own file
        self.assertEqual(len(data["git"]["head"]), 40)
        self.assertEqual(stat.S_IMODE(os.stat(self.ckpt).st_mode), 0o600)
        self.assertEqual([p.name for p in self.ckpt.parent.iterdir() if p.suffix == ".tmp"], [])   # no tmp left behind
        self.assertNotIn("s3", self.calls)

    def test_other_files_under_project_dir_are_still_reported(self):
        (self.root / ".project").mkdir(exist_ok=True)
        (self.root / ".project" / "NOTES.md").write_text("n\n")
        self.make({"s1": orch.RateLimited(1)}).run(self.plan())
        self.assertIn(".project/NOTES.md", json.loads(self.ckpt.read_text())["git"]["pending_edits"])

    def test_rate_limit_detected_from_command_output(self):
        o = self.make({"s1": (1, "curl: HTTP 429 Too Many Requests\nRetry-After: 5")})
        self.assertEqual(o.run(self.plan()), orch.EXIT_RATE_LIMITED)
        self.assertEqual(json.loads(self.ckpt.read_text())["retry_after_seconds"], 5)

    def test_resume_continues_after_the_completed_steps_only(self):
        self.assertEqual(self.make({"s2": orch.RateLimited(0)}).run(self.plan()), orch.EXIT_RATE_LIMITED)
        self.calls.clear()
        self.assertEqual(self.make().resume(), orch.EXIT_OK)
        self.assertEqual(self.calls, ["s2", "s3"])
        self.assertFalse(self.ckpt.exists())

    def test_resume_waits_for_retry_after_unless_told_not_to(self):
        clock = [1000.0]
        o = self.make({"s1": orch.RateLimited(60)}, now=lambda: clock[0])
        o.run(self.plan())
        self.calls.clear()
        clock[0] = 1010.0
        self.assertEqual(self.make(now=lambda: clock[0]).resume(wait=False), orch.EXIT_RATE_LIMITED)
        self.assertEqual(self.calls, [])                              # nothing executed too early
        self.assertEqual(self.make(now=lambda: clock[0]).resume(wait=True), orch.EXIT_OK)
        self.assertEqual(self.calls[0][0], "sleep")
        self.assertAlmostEqual(self.calls[0][1], 50.0, delta=0.5)

    def test_second_rate_limit_during_resume_rewrites_the_checkpoint(self):
        self.make({"s2": orch.RateLimited(0)}).run(self.plan())
        self.assertEqual(self.make({"s3": orch.RateLimited(0)}).resume(), orch.EXIT_RATE_LIMITED)
        data = json.loads(self.ckpt.read_text())
        self.assertEqual(data["progress"]["completed"], ["s1", "s2"])
        self.assertEqual(data["progress"]["pending"], "s3")

    def test_non_rate_limit_failure_exits_1_and_is_not_reported_as_throttling(self):
        self.assertEqual(self.make({"s2": (2, "AssertionError")}).run(self.plan()), orch.EXIT_FAILED)
        data = json.loads(self.ckpt.read_text())
        self.assertEqual(data["state"], "failed")
        self.assertEqual(data["progress"]["pending"], "s2")

    def test_resume_without_a_checkpoint_is_a_usage_error(self):
        self.assertEqual(self.make().resume(), orch.EXIT_USAGE)


class InputFingerprint(Base):
    """GPT review: resume must not reuse a passed step after the content of its inputs changed."""

    def throttled(self, edit):
        edit()                                           # state present when step 1 passes
        self.make({"s2": orch.RateLimited(0)}).run(self.plan())
        self.calls.clear()

    def test_changed_tracked_file_content_is_refused(self):
        self.throttled(lambda: (self.root / "a.txt").write_text("two\n"))
        (self.root / "a.txt").write_text("three\n")     # same HEAD, same path set, different content
        self.assertEqual(self.make().resume(), orch.EXIT_USAGE)
        self.assertEqual(self.calls, [])

    def test_changed_untracked_file_content_is_refused(self):
        self.throttled(lambda: (self.root / "new.txt").write_text("x\n"))
        (self.root / "new.txt").write_text("y\n")
        self.assertEqual(self.make().resume(), orch.EXIT_USAGE)
        self.assertEqual(self.calls, [])

    def test_unchanged_inputs_still_resume(self):
        self.throttled(lambda: (self.root / "new.txt").write_text("x\n"))
        self.assertEqual(self.make().resume(), orch.EXIT_OK)
        self.assertEqual(self.calls, ["s2", "s3"])

    def test_deliberate_override_reruns_every_step(self):
        self.throttled(lambda: (self.root / "a.txt").write_text("two\n"))
        (self.root / "a.txt").write_text("three\n")
        self.assertEqual(self.make().resume(allow_input_change=True), orch.EXIT_OK)
        self.assertEqual(self.calls, ["s1", "s2", "s3"])   # nothing passed on the old inputs is reused

    def test_deleted_input_is_detected(self):
        self.throttled(lambda: (self.root / "new.txt").write_text("x\n"))
        (self.root / "new.txt").unlink()
        self.assertEqual(self.make().resume(), orch.EXIT_USAGE)

    def test_fingerprint_covers_bytes_past_the_diff_cap(self):
        big = "x" * (orch.MAX_DIFF_BYTES + 10)
        self.throttled(lambda: (self.root / "big.txt").write_text(big + "A"))
        (self.root / "big.txt").write_text(big + "B")
        self.assertEqual(self.make().resume(), orch.EXIT_USAGE)


class InputsEditedByFailingStep(Base):
    """Codex P2 on 5434e78: a later step that edits an input and then fails/throttles must not let --resume skip the
    validations that passed against the original contents."""

    def edit_then(self, outcome):
        def behave():
            (self.root / "a.txt").write_text("invalid\n")
            if isinstance(outcome, Exception):
                raise outcome
            return outcome
        return behave

    def test_throttled_step_that_edited_an_input_blocks_resume(self):
        self.make({"s2": self.edit_then(orch.RateLimited(0))}).run(self.plan())
        self.calls.clear()
        self.assertEqual(self.make().resume(), orch.EXIT_USAGE)
        self.assertEqual(self.calls, [])

    def test_failed_step_that_edited_an_input_blocks_resume(self):
        self.make({"s2": self.edit_then((1, "boom"))}).run(self.plan())
        self.calls.clear()
        self.assertEqual(self.make().resume(), orch.EXIT_USAGE)
        self.assertEqual(self.calls, [])

    def test_override_reruns_every_step_on_the_edited_inputs(self):
        self.make({"s2": self.edit_then(orch.RateLimited(0))}).run(self.plan())
        self.calls.clear()
        self.assertEqual(self.make().resume(allow_input_change=True), orch.EXIT_OK)
        self.assertEqual(self.calls, ["s1", "s2", "s3"])

    def test_throttle_without_edits_still_resumes_from_the_pending_step(self):
        self.make({"s2": orch.RateLimited(0)}).run(self.plan())
        self.calls.clear()
        self.assertEqual(self.make().resume(), orch.EXIT_OK)
        self.assertEqual(self.calls, ["s2", "s3"])


class GitInvocationHardening(Base):
    """Scanner threads #9697/#9698: `git` must not be resolved through a repo-controlled PATH entry, and ambient GIT_*
    variables must not redirect it."""

    def test_git_is_an_absolute_path_with_an_allowlisted_environment(self):
        seen = {}

        def fake_run(argv, **kwargs):
            seen["argv"], seen["env"] = argv, kwargs["env"]
            return subprocess.CompletedProcess(argv, 0, stdout="x\n", stderr="")
        hostile = {"GIT_DIR": "/elsewhere", "GIT_WORK_TREE": "/elsewhere", "GIT_INDEX_FILE": "/elsewhere/i",
                   "GIT_EXTERNAL_DIFF": "/bin/false", "GIT_CONFIG_COUNT": "1", "SECRET_TOKEN": "s3cret"}
        with mock.patch.dict(os.environ, hostile), mock.patch.object(orch.subprocess, "run", fake_run):
            self.assertEqual(orch._git(self.root, "status"), (0, "x\n"))
        self.assertTrue(os.path.isabs(seen["argv"][0]), seen["argv"])
        self.assertEqual(seen["env"].get("GIT_TERMINAL_PROMPT"), "0")
        for name in hostile:
            self.assertNotIn(name, seen["env"])

    def test_a_git_planted_inside_the_repository_is_never_executed(self):
        marker = self.root / "planted-ran"
        planted = self.root / "git"
        planted.write_text(f"#!/bin/sh\ntouch {marker}\nexit 0\n")
        planted.chmod(0o755)
        with mock.patch.dict(os.environ, {"PATH": f"{self.root}{os.pathsep}{os.environ['PATH']}"}):
            code, _ = orch._git(self.root, "rev-parse", "HEAD")
        self.assertFalse(marker.exists(), "a repo-local git binary was executed")
        self.assertEqual(code, 0)                       # the real git, found later on PATH, still works

    def test_missing_git_fails_closed(self):
        with mock.patch.dict(os.environ, {"PATH": str(self.root)}):
            self.assertEqual(orch._git(self.root, "status")[0], 127)


class SingleExecutor(Base):
    """Codex P2 on 5434e78: a second invocation must not run steps while another executor owns the checkpoint."""

    def test_resume_and_run_are_refused_while_a_plan_is_executing(self):
        seen = {}

        def intrude():
            seen["resume"] = self.make().resume(wait=False)
            seen["run"] = self.make().run(self.plan(ids=("x1",)))
            return None
        self.assertEqual(self.make({"s2": intrude}).run(self.plan()), orch.EXIT_OK)
        self.assertEqual(seen, {"resume": orch.EXIT_USAGE, "run": orch.EXIT_USAGE})
        self.assertEqual(self.calls, ["s1", "s2", "s3"])           # nothing ran twice, "x1" never ran

    def test_lock_is_released_after_the_run_and_after_a_failure(self):
        self.assertEqual(self.make({"s2": (1, "boom")}).run(self.plan()), orch.EXIT_FAILED)
        self.assertEqual(self.make().run(self.plan()), orch.EXIT_OK)

    def test_lock_file_is_not_an_input_change(self):
        self.make({"s2": orch.RateLimited(0)}).run(self.plan())
        self.calls.clear()
        self.assertEqual(self.make().resume(), orch.EXIT_OK)
        self.assertEqual(self.calls, ["s2", "s3"])


class BoundedOutput(Base):
    def test_huge_output_is_bounded_and_an_early_rate_limit_is_still_detected(self):
        code = ("import sys\nsys.stderr.write('HTTP 429 Too Many Requests retry-after: 7\\n')\n"
                "chunk='x'*65536\n"
                "for _ in range(320):\n    sys.stdout.write(chunk)\n"
                "sys.exit(1)\n")
        o = orch.Orchestrator(root=self.root, checkpoint=self.ckpt, sleep=lambda s: None)
        rc, out = o._subprocess_runner({"id": "t", "argv": [sys.executable, "-c", code], "timeout": 120})
        self.assertEqual(rc, 1)
        self.assertLess(len(out), 1_000_000)                      # 20 MiB were written
        self.assertEqual(orch.detect_rate_limit(rc, out), (True, 7.0))

    def run_chunks(self, chunks, exit_code=1):
        code = ("import sys,time\n"
                f"for c in {chunks!r}:\n    sys.stdout.write(c); sys.stdout.flush(); time.sleep(0.3)\n"
                f"sys.exit({exit_code})\n")
        o = orch.Orchestrator(root=self.root, checkpoint=self.ckpt, sleep=lambda s: None)
        rc, out = o._subprocess_runner({"id": "t", "argv": [sys.executable, "-c", code], "timeout": 60})
        return rc, out

    def test_retry_after_split_across_reads_is_not_truncated(self):
        rc, out = self.run_chunks(["HTTP 429\nRetry-After: 1", "20\n", "x" * 100_000])
        self.assertEqual(orch.detect_rate_limit(rc, out), (True, 120.0))

    def test_retry_after_at_end_of_output_is_accepted_on_eof(self):
        rc, out = self.run_chunks(["HTTP 429\nRetry-After: 45"])
        self.assertEqual(orch.detect_rate_limit(rc, out), (True, 45.0))

    def test_status_number_split_across_reads_is_not_a_false_429(self):
        rc, out = self.run_chunks(["HTTP 429", "5 internal build id\n", "y" * 100_000])
        self.assertEqual(orch.detect_rate_limit(rc, out), (False, None))

    def test_ordinary_output_is_returned_whole(self):
        o = orch.Orchestrator(root=self.root, checkpoint=self.ckpt, sleep=lambda s: None)
        rc, out = o._subprocess_runner({"id": "t", "argv": [sys.executable, "-c",
                                        "import sys; print('out'); print('err', file=sys.stderr)"], "timeout": 30})
        self.assertEqual(rc, 0)
        self.assertIn("out", out)
        self.assertIn("err", out)


class SuccessfulStepEditsInputs(Base):
    """Codex P2 on 9c6eef0: a step that edits inputs and *succeeds* must still invalidate earlier validations."""

    def ids(self):
        return self.plan(ids=("validate", "edit", "remote"))

    def edit_ok(self):
        (self.root / "a.txt").write_text("invalid\n")
        return (0, "ok")

    def test_validation_before_a_successful_edit_is_rerun_on_resume(self):
        self.make({"edit": self.edit_ok, "remote": orch.RateLimited(0)}).run(self.ids())
        self.assertEqual(self.calls, ["validate", "edit", "validate", "remote"])   # re-validated before the 429
        self.calls.clear()
        self.assertEqual(self.make().resume(), orch.EXIT_OK)
        self.assertEqual(self.calls, ["remote"])                  # both validate (on the final inputs) and edit are kept

    def test_the_editing_step_itself_is_not_repeated(self):
        self.make({"edit": self.edit_ok, "remote": (1, "boom")}).run(self.ids())
        self.calls.clear()
        self.make().resume()
        self.assertNotIn("edit", self.calls)

    def test_an_edit_by_the_first_step_invalidates_nothing(self):
        self.make({"validate": self.edit_ok, "edit": orch.RateLimited(0)}).run(self.ids())
        self.calls.clear()
        self.assertEqual(self.make().resume(), orch.EXIT_OK)
        self.assertEqual(self.calls, ["edit", "remote"])

    def test_steps_that_change_nothing_keep_their_progress(self):
        self.make({"remote": orch.RateLimited(0)}).run(self.ids())
        self.calls.clear()
        self.assertEqual(self.make().resume(), orch.EXIT_OK)
        self.assertEqual(self.calls, ["remote"])


class SuccessPathRevalidation(Base):
    """GPT review on 8d46332: with no 429 at all, a plan must not report success while an earlier validation has not
    passed on the final inputs."""

    def ids(self):
        return self.plan(ids=("validate", "edit", "remote"))

    def edit_once(self, count):
        def behave():
            count.append(1)
            (self.root / "a.txt").write_text(f"edit-{len(count)}\n")
            return (0, "ok")
        return behave

    def test_validation_reruns_on_the_final_inputs_before_success(self):
        self.assertEqual(self.make({"edit": self.edit_once([])}).run(self.ids()), orch.EXIT_OK)
        self.assertEqual(self.calls, ["validate", "edit", "validate", "remote"])    # validate ran after the edit
        self.assertFalse(self.ckpt.exists())

    def test_a_validation_that_itself_keeps_changing_inputs_fails_closed(self):
        flapping = []
        behaviour = {"validate": self.edit_once(flapping)}            # every validate rewrites the file
        code = self.make(behaviour).run(self.plan(ids=("validate", "remote")))
        self.assertEqual(code, orch.EXIT_OK)                          # a first-step mutation invalidates nothing

    def test_a_late_mutation_triggers_exactly_one_revalidation(self):
        count = []
        code = self.make({"remote": self.edit_once(count)}).run(self.plan(ids=("validate", "remote")))
        self.assertEqual(code, orch.EXIT_OK)
        self.assertEqual(self.calls, ["validate", "remote", "validate"])   # re-run on the final inputs, remote kept
        self.assertEqual(len(count), 1)

    def test_replays_that_never_settle_fail_with_a_checkpoint(self):
        shared = []                                               # one counter, so every call writes new content
        behaviour = {"edit": self.edit_once(shared), "remote": self.edit_once(shared)}
        code = self.make(behaviour).run(self.ids())
        self.assertEqual(code, orch.EXIT_FAILED)
        self.assertTrue(self.ckpt.exists())
        self.assertIn("inputs", json.loads(self.ckpt.read_text())["reason"])


class SpecialPathsAndInterrupts(Base):
    """Codex P2s on 07d9bd2: escaped git paths must still be fingerprinted; Ctrl-C must not orphan a step."""

    def test_non_ascii_and_quoted_names_are_fingerprinted(self):
        for name in ("caf\u00e9.txt", 'quo"te.txt', "tab\there.txt", "sp ace.txt"):
            with self.subTest(name=name):
                (self.root / name).write_text("x\n")
                self.make({"s2": orch.RateLimited(0)}).run(self.plan())
                self.calls.clear()
                (self.root / name).write_text("y\n")
                self.assertEqual(self.make().resume(), orch.EXIT_USAGE)
                self.assertEqual(self.calls, [])
                (self.root / name).unlink()
                self.ckpt.unlink(missing_ok=True)

    def test_renamed_file_is_tracked_by_its_new_name(self):
        git(self.root, "mv", "a.txt", "b.txt")
        snap = orch.git_snapshot(self.root)
        self.assertIn("b.txt", snap["pending_edits"])

    def test_keyboard_interrupt_terminates_the_step_and_its_children(self):
        marker = self.root / "marker"
        child = "import pathlib,sys,time; time.sleep(1.5); pathlib.Path(sys.argv[1]).write_text('x')"
        parent = ("import subprocess,sys,time\n"
                  "subprocess.Popen([sys.executable,'-c',sys.argv[2],sys.argv[1]])\n"
                  "time.sleep(30)\n")
        real, fired = subprocess.Popen.wait, []

        def interrupted(proc, *args, **kwargs):
            if not fired:
                fired.append(1)
                time.sleep(0.3)                      # let the child start
                raise KeyboardInterrupt
            return real(proc, *args, **kwargs)
        o = orch.Orchestrator(root=self.root, checkpoint=self.ckpt, sleep=lambda s: None)
        with mock.patch.object(subprocess.Popen, "wait", interrupted):
            with self.assertRaises(KeyboardInterrupt):
                o._subprocess_runner({"id": "t", "argv": [sys.executable, "-c", parent, str(marker), child], "timeout": 30})
        time.sleep(2.2)
        self.assertFalse(marker.exists(), "the interrupted step's descendant kept running")


class SigtermAndRawBytes(Base):
    """Codex P2s on cac0c75."""

    def test_non_utf8_filename_is_fingerprinted_without_crashing(self):
        raw = os.fsencode(str(self.root)) + b"/bad\xff.txt"
        with open(raw, "wb") as handle:
            handle.write(b"one")
        first = orch.git_snapshot(self.root)
        self.assertTrue(first["available"])
        with open(raw, "wb") as handle:
            handle.write(b"two")
        self.assertNotEqual(first["content_sha256"], orch.git_snapshot(self.root)["content_sha256"])

    def test_sigterm_to_the_cli_terminates_the_running_step(self):
        started, marker = self.root / "started", self.root / "marker"
        code = ("import pathlib,sys,time; pathlib.Path(sys.argv[1]).write_text('x'); time.sleep(1.5); "
                "pathlib.Path(sys.argv[2]).write_text('x')")
        plan = self.root / "plan.json"
        plan.write_text(json.dumps({"context": {}, "steps": [
            {"id": "s1", "argv": ["true"]},
            {"id": "s2", "argv": [sys.executable, "-c", code, str(started), str(marker)], "timeout": 60}]}))
        script = pathlib.Path(orch.__file__).resolve()
        proc = subprocess.Popen([sys.executable, str(script), "--plan", str(plan), "--root", str(self.root),
                                 "--checkpoint", str(self.ckpt)], stderr=subprocess.DEVNULL)
        deadline = time.time() + 20
        while not started.exists() and time.time() < deadline:
            time.sleep(0.05)
        self.assertTrue(started.exists(), "step never started")
        proc.send_signal(__import__("signal").SIGTERM)
        self.assertNotEqual(proc.wait(timeout=20), 0)
        time.sleep(2.2)
        self.assertFalse(marker.exists(), "SIGTERM left the step running")


class WaitAndLeaderExit(Base):
    """Codex P2s on ad91d8f."""

    def test_background_child_of_a_finished_step_is_cleaned_up(self):
        marker = self.root / "marker"
        child = "import pathlib,sys,time; time.sleep(1.5); pathlib.Path(sys.argv[1]).write_text('x')"
        leader = ("import subprocess,sys\n"
                  "subprocess.Popen([sys.executable,'-c',sys.argv[2],sys.argv[1]],"
                  "stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n")
        o = orch.Orchestrator(root=self.root, checkpoint=self.ckpt, sleep=lambda s: None)
        code, _ = o._subprocess_runner({"id": "t", "argv": [sys.executable, "-c", leader, str(marker), child], "timeout": 30})
        self.assertEqual(code, 0)
        time.sleep(2.2)
        self.assertFalse(marker.exists(), "a background child outlived its finished step")

    def _throttled_with_wait(self):
        clock = [1000.0]
        self.make({"s2": orch.RateLimited(60)}, now=lambda: clock[0]).run(self.plan())
        self.calls.clear()
        return clock

    def test_input_change_during_retry_wait_is_refused(self):
        clock = self._throttled_with_wait()
        o = self.make(sleep=lambda s: (self.root / "a.txt").write_text("changed while waiting\n"), now=lambda: clock[0])
        self.assertEqual(o.resume(wait=True), orch.EXIT_USAGE)
        self.assertEqual(self.calls, [])

    def test_head_change_during_retry_wait_is_refused(self):
        clock = self._throttled_with_wait()

        def commit_while_waiting(_seconds):
            (self.root / "b.txt").write_text("b\n")
            git(self.root, "add", "b.txt")
            git(self.root, "commit", "-q", "-m", "during wait")
        o = self.make(sleep=commit_while_waiting, now=lambda: clock[0])
        self.assertEqual(o.resume(wait=True), orch.EXIT_USAGE)
        self.assertEqual(self.calls, [])

    def test_head_change_during_wait_with_override_reruns_every_step(self):
        clock = self._throttled_with_wait()

        def commit_while_waiting(_seconds):
            (self.root / "b.txt").write_text("b\n")
            git(self.root, "add", "b.txt")
            git(self.root, "commit", "-q", "-m", "during wait")
        o = self.make(sleep=commit_while_waiting, now=lambda: clock[0])
        self.assertEqual(o.resume(wait=True, allow_head_change=True), orch.EXIT_OK)
        self.assertEqual(self.calls, ["s1", "s2", "s3"])      # nothing from the old commit is reused

    def test_unchanged_state_after_the_wait_still_resumes(self):
        clock = self._throttled_with_wait()
        self.assertEqual(self.make(sleep=lambda s: None, now=lambda: clock[0]).resume(wait=True), orch.EXIT_OK)
        self.assertEqual(self.calls, ["s2", "s3"])


class HeadMovesDuringExecution(Base):
    """Codex P2 on d4825be: steps completed on one commit must not be reused after HEAD moves mid-run."""

    def commit_input(self):
        (self.root / "a.txt").write_text("changed by a step\n")
        git(self.root, "commit", "-q", "-am", "step commits")

    def test_head_move_before_a_throttle_invalidates_completed_steps(self):
        o = self.make({"s2": lambda: (self.commit_input(), orch.RateLimited(0))[1]})
        self.assertEqual(o.run(self.plan()), orch.EXIT_FAILED)
        data = json.loads(self.ckpt.read_text())
        self.assertEqual(data["progress"]["completed"], [])
        self.calls.clear()
        self.assertEqual(self.make().resume(), orch.EXIT_OK)          # no override needed: nothing is reused
        self.assertEqual(self.calls, ["s1", "s2", "s3"])

    def test_head_move_during_a_successful_step_stops_the_run(self):
        o = self.make({"s2": lambda: (self.commit_input(), (0, "ok"))[1]})
        self.assertEqual(o.run(self.plan()), orch.EXIT_FAILED)
        self.assertNotIn("s3", self.calls)
        self.assertEqual(json.loads(self.ckpt.read_text())["progress"]["completed"], [])

    def test_stable_head_is_unaffected(self):
        self.assertEqual(self.make().run(self.plan()), orch.EXIT_OK)
        self.assertEqual(self.calls, ["s1", "s2", "s3"])


class CheckpointSafety(Base):
    def checkpointed(self):
        self.make({"s2": orch.RateLimited(0)}).run(self.plan())
        self.calls.clear()

    def test_tampered_checkpoint_is_rejected(self):
        self.checkpointed()
        data = json.loads(self.ckpt.read_text())
        data["progress"]["completed"] = ["s1", "s2", "s3"]
        self.ckpt.write_text(json.dumps(data))
        self.assertEqual(self.make().resume(), orch.EXIT_USAGE)
        self.assertEqual(self.calls, [])

    def test_unknown_version_and_garbage_are_rejected(self):
        self.checkpointed()
        self.ckpt.write_text("not json")
        self.assertEqual(self.make().resume(), orch.EXIT_USAGE)

    def test_resume_refuses_when_head_changed_unless_allowed(self):
        self.checkpointed()
        (self.root / "b.txt").write_text("b\n")
        git(self.root, "add", "b.txt")
        git(self.root, "commit", "-q", "-m", "other work")
        self.assertEqual(self.make().resume(), orch.EXIT_USAGE)
        self.assertEqual(self.calls, [])
        self.assertEqual(self.make().resume(allow_head_change=True), orch.EXIT_OK)
        # GPT review: steps that passed on the old commit are not evidence for the new one
        self.assertEqual(self.calls, ["s1", "s2", "s3"])

    def test_head_change_override_also_reruns_everything_when_inputs_changed_too(self):
        self.checkpointed()
        (self.root / "a.txt").write_text("changed and committed\n")
        git(self.root, "commit", "-q", "-am", "change a tracked input")
        (self.root / "new.txt").write_text("and a dirty file\n")
        self.assertEqual(self.make().resume(allow_head_change=True), orch.EXIT_USAGE)   # content changed as well
        self.assertEqual(self.calls, [])
        self.assertEqual(self.make().resume(allow_head_change=True, allow_input_change=True), orch.EXIT_OK)
        self.assertEqual(self.calls, ["s1", "s2", "s3"])

    def test_unchanged_head_still_reuses_completed_steps(self):
        self.checkpointed()
        self.assertEqual(self.make().resume(allow_head_change=True), orch.EXIT_OK)
        self.assertEqual(self.calls, ["s2", "s3"])

    def test_secrets_are_redacted_and_secret_files_never_enter_the_diff(self):
        (self.root / ".env").write_text("API_KEY=supersecretvalue\n")
        git(self.root, "add", "-f", ".env")
        git(self.root, "commit", "-q", "-m", "oops tracked env")
        (self.root / ".env").write_text("API_KEY=changedsecretvalue\n")
        (self.root / "a.txt").write_text("one\nvisible-change\n")
        o = self.make({"s1": (1, "429 Too Many Requests\nAuthorization: Bearer abc.def.ghi\napi_key=hunter2hunter2")})
        o.run(self.plan())
        raw = self.ckpt.read_text()
        self.assertNotIn("changedsecretvalue", raw)
        self.assertNotIn("supersecretvalue", raw)
        self.assertNotIn("abc.def.ghi", raw)
        self.assertNotIn("hunter2hunter2", raw)
        self.assertIn("visible-change", raw)

    def test_diff_is_size_bounded(self):
        (self.root / "a.txt").write_text("x" * (orch.MAX_DIFF_BYTES * 3))
        self.make({"s1": orch.RateLimited(1)}).run(self.plan())
        data = json.loads(self.ckpt.read_text())
        self.assertTrue(data["git"]["diff_truncated"])
        self.assertLessEqual(len(data["git"]["diff"].encode()), orch.MAX_DIFF_BYTES)


class Redaction(unittest.TestCase):
    def test_quoted_json_keys_and_values_are_redacted(self):
        for raw, secret in [('{"api_key": "supersecretvalue"}', "supersecretvalue"),
                            ("{'token': 'abc123xyz'}", "abc123xyz"),
                            ('{"password": "has spaces in it"}', "has spaces in it"),
                            ('{"client_secret":"s3cr3t-value"}', "s3cr3t-value"),
                            ("GITHUB_TOKEN=ghp_abcdef123456", "ghp_abcdef123456"),
                            ("AWS_SECRET_ACCESS_KEY: wJalrXUtnFEMI", "wJalrXUtnFEMI"),
                            ('password = "two words"', "two words")]:
            out = orch.redact(raw)
            self.assertNotIn(secret, out, raw)
            self.assertIn("[REDACTED]", out, raw)

    def test_whole_authorization_values_are_redacted(self):
        for raw, secret in [("Authorization: Basic dXNlcjpwYXNz", "dXNlcjpwYXNz"),
                            ("authorization=Token abc.def", "abc.def"),
                            ('{"Authorization": "Basic dXNlcjpwYXNz"}', "dXNlcjpwYXNz"),
                            ("Authorization: Bearer abc.def.ghi", "abc.def.ghi")]:
            out = orch.redact(raw)
            self.assertNotIn(secret, out, raw)
            if "Basic" in raw:
                self.assertNotIn("Basic", out)

    def test_ordinary_text_is_left_alone(self):
        text = "compiling 3 files; token count is not a secret here\nline two"
        self.assertEqual(orch.redact(text), text)

    def test_checkpoint_never_contains_quoted_secrets_in_tail_or_diff(self):
        d = tempfile.TemporaryDirectory()
        root = pathlib.Path(d.name)
        git(root, "init", "-q")
        (root / "c.json").write_text("{}\n")
        git(root, "add", "c.json")
        git(root, "commit", "-q", "-m", "i")
        (root / "c.json").write_text('{"api_key": "quotedsecretvalue", "password": "a b c d"}\n')
        ck = root / ".project" / "checkpoint.json"
        o = orch.Orchestrator(root=root, checkpoint=ck, runner=lambda s: (1, 'HTTP 429\n{"token": "tailsecretvalue"}'),
                              sleep=lambda s: None)
        o.run({"steps": [{"id": "x", "argv": ["true"]}]})
        raw = ck.read_text()
        for secret in ["quotedsecretvalue", "a b c d", "tailsecretvalue"]:
            self.assertNotIn(secret, raw)
        d.cleanup()


class GameplayIdentifiers(unittest.TestCase):
    """Codex P1: player/request/inventory identifiers must not be persisted in checkpoint diagnostics."""

    def test_identifiers_are_redacted_in_json_and_key_value_forms(self):
        for text in ('{"playerId":"private-player-identifier","requestId":"private-request-identifier",'
                     '"inventoryId":"private-inventory-identifier"}',
                     "player_id=private-player-identifier request-id: private-request-identifier",
                     "{'inventory_id': 'private-inventory-identifier'}"):
            out = orch.redact(text)
            self.assertNotIn("private-", out, out)

    def test_unrelated_text_is_unchanged(self):
        text = "step build failed: 3 tests, valid=false, hostId unknown"
        self.assertEqual(orch.redact(text), text)

    def test_checkpoint_tail_never_contains_identifiers(self):
        self.assertNotIn("private-", orch.redact("noise " * 50 + '{"playerId":"private-x"}'))


class TimeoutKillsDescendants(Base):
    def test_a_timed_out_step_does_not_leave_children_running(self):
        marker = self.root / "child-ran.flag"
        child = ("import pathlib,time,sys\ntime.sleep(1.5)\npathlib.Path(sys.argv[1]).write_text('x')\n")
        parent = ("import subprocess,sys,time\n"
                  "subprocess.Popen([sys.executable,'-c',sys.argv[2],sys.argv[1]])\n"
                  "time.sleep(30)\n")
        o = orch.Orchestrator(root=self.root, checkpoint=self.ckpt, sleep=lambda s: None)
        code, _ = o._subprocess_runner({"id": "t", "argv": [sys.executable, "-c", parent, str(marker), child], "timeout": 1})
        self.assertEqual(code, 124)
        time.sleep(2.2)
        self.assertFalse(marker.exists(), "a descendant of the timed-out step kept running")


class RealSubprocess(Base):
    def test_a_real_command_printing_429_triggers_the_checkpoint_and_resume_finishes(self):
        # External retry state, deliberately outside the repo: a file the throttled step created inside the tree would
        # be an input change and (correctly) block --resume.
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        flag = pathlib.Path(scratch.name) / "ok.flag"
        script = ("import pathlib,sys\nf=pathlib.Path(sys.argv[1])\n"
                  "if not f.exists():\n    f.write_text('x'); print('HTTP 429 Too Many Requests', file=sys.stderr); sys.exit(1)\n")
        plan = {"context": {}, "steps": [
            {"id": "first", "argv": [sys.executable, "-c", "print('hello')"]},
            {"id": "limited", "argv": [sys.executable, "-c", script, str(flag)]}]}
        o = orch.Orchestrator(root=self.root, checkpoint=self.ckpt, sleep=lambda s: None)
        self.assertEqual(o.run(plan), orch.EXIT_RATE_LIMITED)
        self.assertEqual(json.loads(self.ckpt.read_text())["progress"]["pending"], "limited")
        self.assertEqual(orch.Orchestrator(root=self.root, checkpoint=self.ckpt, sleep=lambda s: None).resume(), orch.EXIT_OK)


if __name__ == "__main__":
    unittest.main()
