import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import unittest

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

    def test_success_is_never_a_rate_limit(self):
        self.assertFalse(orch.detect_rate_limit(0, "HTTP 429 mentioned in a log line")[0])

    def test_parses_retry_after_seconds_and_caps_it(self):
        self.assertEqual(orch.detect_rate_limit(1, "429 Too Many Requests\nRetry-After: 42"), (True, 42.0))
        self.assertEqual(orch.detect_rate_limit(1, "429 retry-after=999999")[1], orch.MAX_RETRY_AFTER)
        self.assertIsNone(orch.detect_rate_limit(1, "429")[1])


class Plan(Base):
    def test_rejects_duplicate_ids_empty_plans_and_shell_strings(self):
        for bad in [{"steps": []}, self.plan(("a", "a")), {"steps": [{"id": "x", "argv": "echo hi"}]},
                    {"steps": [{"id": "bad id!", "argv": ["true"]}]}, {"steps": [{"id": "x", "argv": []}]}]:
            with self.assertRaises(orch.PlanError):
                orch.validate_plan(bad)


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
        self.assertEqual([p.name for p in self.ckpt.parent.iterdir()], ["checkpoint.json"])   # no tmp left behind
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


class RealSubprocess(Base):
    def test_a_real_command_printing_429_triggers_the_checkpoint_and_resume_finishes(self):
        flag = self.root / "ok.flag"
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
