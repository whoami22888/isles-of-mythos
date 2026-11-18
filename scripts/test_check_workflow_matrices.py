import pathlib
import tempfile
import unittest

import check_workflow_matrices as guard


def run(text):
    """Return guard diagnostics for a temporary workflow document."""
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d)
        (p / "w.yml").write_text(text)
        return guard.check(p)


class WorkflowMatrixGuard(unittest.TestCase):
    """Regression tests for workflow-matrix fail-fast policy."""
    def test_matrix_with_fail_fast_false_passes(self):
        """Verify a matrix with fail-fast disabled passes."""
        self.assertEqual(run("jobs:\n  t:\n    strategy:\n      fail-fast: false\n      matrix:\n        a: [1, 2]\n    steps: []\n"), [])

    def test_matrix_without_fail_fast_is_rejected(self):
        """Reject a matrix that omits fail-fast."""
        self.assertTrue(run("jobs:\n  t:\n    strategy:\n      matrix:\n        a: [1, 2]\n    steps: []\n"))

    def test_fail_fast_true_is_rejected(self):
        """Reject a matrix that enables fail-fast."""
        self.assertTrue(run("jobs:\n  t:\n    strategy:\n      fail-fast: true\n      matrix:\n        a: [1]\n"))

    def test_strategy_without_matrix_is_ignored(self):
        """Ignore a strategy that does not define a matrix."""
        self.assertEqual(run("jobs:\n  t:\n    strategy:\n      max-parallel: 1\n    steps: []\n"), [])

    def test_fail_fast_in_another_jobs_strategy_does_not_count(self):
        """Keep matrix strategies isolated by job."""
        text = ("jobs:\n  a:\n    strategy:\n      fail-fast: false\n      matrix:\n        x: [1]\n"
                "  b:\n    strategy:\n      matrix:\n        y: [1]\n")
        self.assertEqual(len(run(text)), 1)

    def test_dynamic_matrix_expression_still_requires_fail_fast(self):
        """Reject an unverifiable dynamic matrix without fail-fast."""
        self.assertTrue(run("jobs:\n  t:\n    strategy:\n      matrix: ${{ fromJson(needs.p.outputs.m) }}\n"))

    def test_flow_mapping_strategy_without_fail_fast_is_rejected(self):
        """Reject a flow-mapped matrix without fail-fast."""
        self.assertTrue(run("jobs:\n  t:\n    strategy: {matrix: {os: [a, b]}}\n    steps: []\n"))

    def test_flow_mapping_strategy_with_fail_fast_false_passes(self):
        """Accept a flow-mapped matrix with fail-fast disabled."""
        self.assertEqual(run("jobs:\n  t:\n    strategy: {fail-fast: false, matrix: {os: [a, b]}}\n    steps: []\n"), [])

    def test_quoted_or_string_false_is_not_accepted(self):
        """Reject string values that are not boolean false."""
        self.assertTrue(run("jobs:\n  t:\n    strategy:\n      fail-fast: 'false'\n      matrix:\n        a: [1]\n"))

    def test_whole_strategy_as_an_expression_is_rejected_as_unverifiable(self):
        """Reject an unverifiable dynamic strategy."""
        self.assertTrue(run("jobs:\n  t:\n    strategy: ${{ fromJson(needs.p.outputs.s) }}\n    steps: []\n"))

    def test_unparseable_workflow_fails_closed(self):
        """Fail closed when workflow YAML cannot be parsed."""
        self.assertTrue(run("jobs: [unclosed\n"))

    def test_redis_matrix_probe_accepts_final_attempt_and_fails_closed(self):
        """Cover Redis readiness on the final allowed attempt."""
        workflow = (guard.WORKFLOWS / "ci.yml").read_text()
        start = workflow.index("      - name: Start Redis and migrate integration database")
        end = workflow.index("      - name: Server integration tests", start)
        redis_step = workflow[start:end]
        self.assertIn("redis_ready=false", redis_step)
        self.assertIn('if [[ "$reply" == +PONG* ]]; then', redis_step)
        self.assertIn("redis_ready=true", redis_step)
        self.assertIn('if [ "$redis_ready" != true ]; then', redis_step)
        self.assertNotIn('if [ "$attempt" -eq 30 ]; then', redis_step)

        def ready_after(replies):
            """Return whether any probe received a valid PONG."""
            redis_ready = False
            for reply in replies:
                if reply.startswith("+PONG"):
                    redis_ready = True
                    break
            return redis_ready

        self.assertTrue(ready_after(["-LOADING\r\n"] * 29 + ["+PONG\r\n"]))
        self.assertFalse(ready_after(["-LOADING\r\n"] * 30))

    def test_queue_aware_actionlint_is_pinned_and_checks_the_full_workflow(self):
        """Pin actionlint and its scoped test command."""
        workflow = (guard.WORKFLOWS / "ci.yml").read_text()
        self.assertIn("repository: vvoland/actionlint", workflow)
        self.assertIn("ref: 644076a59742c2d1540ebd4686eab3c308f0e562", workflow)
        self.assertIn("actions/setup-go@4dc6199c7b1a012772edbd06daecab0f50c9053c", workflow)
        self.assertIn("go-version: 1.25.0", workflow)
        self.assertRegex(workflow, r"(?m)^[ \t]*GOTOOLCHAIN=local go test -mod=readonly \.$")
        self.assertNotRegex(
            workflow,
            r"(?m)^[ \t]*GOTOOLCHAIN=local go test -mod=readonly \./\.\.\.$",
        )
        self.assertIn(
            '"$RUNNER_TEMP/actionlint" .github/workflows/ci.yml', workflow
        )
        self.assertIn("queue: max", workflow)
        self.assertIn('find "$ANDROID_HOME/build-tools"', workflow)
        self.assertNotIn('ls -1 "$ANDROID_HOME"/build-tools', workflow)

    def test_visual_evidence_forces_mobile_vulkan_and_records_provenance(self):
        """Reject silent OpenGL fallback and require capture provenance."""
        workflow = (guard.WORKFLOWS / "godot-visual-evidence.yml").read_text()
        self.assertIn("mesa-vulkan-drivers", workflow)
        self.assertIn("vulkan-tools", workflow)
        self.assertIn("VK_ICD_FILENAMES", workflow)
        self.assertIn("vulkaninfo --summary", workflow)
        self.assertIn("VK_KHR_surface", workflow)
        self.assertEqual(workflow.count("--rendering-driver vulkan"), 6)
        self.assertIn("switching to OpenGL", workflow)
        self.assertIn("grep -Eq '^Vulkan [0-9]+\\.[0-9]+'", workflow)
        self.assertIn('grep -q "Forward Mobile"', workflow)
        self.assertNotIn('grep -q "Vulkan API"', workflow)
        self.assertIn("SOURCE-SHA.txt", workflow)
        self.assertIn("RENDERER-PROVENANCE.txt", workflow)
        self.assertIn("VULKANINFO-SUMMARY.txt", workflow)
        self.assertIn("CAPTURE-ARTIFACT-SHA256SUMS", workflow)
        self.assertIn("vendor.lock.json", workflow)
        self.assertIn(
            (
                "owner_reference_sha256="
                "713cd6e90c6f7d589a06eb3bd4b9b2d5ebeb9c0ff711b5de527a68460dfbcb05"
            ),
            workflow,
        )
        self.assertIn("visual_acceptance=NOT_VERIFIED", workflow)
        self.assertNotIn('echo "source_sha=', workflow)

    def test_signed_android_artifact_runs_for_any_pull_request_base(self):
        """Keep the signed debug artifact enabled for stacked PR bases."""
        workflow = (guard.WORKFLOWS / "ci.yml").read_text()
        self.assertEqual(
            workflow.count(
                "if: matrix.target == 'godot' && github.event_name == 'pull_request'"
            ),
            2,
        )
        self.assertNotIn("github.base_ref == 'main'", workflow)
        self.assertIn("name: Export and verify signed Android debug APK", workflow)
        self.assertIn("name: Upload signed Android debug APK", workflow)

    def test_repository_workflows_comply(self):
        """Check all repository workflows against the matrix policy."""
        self.assertEqual(guard.check(guard.WORKFLOWS), [])


if __name__ == "__main__":
    unittest.main()
