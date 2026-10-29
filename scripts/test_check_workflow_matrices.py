import pathlib
import tempfile
import unittest

import check_workflow_matrices as guard


def run(text):
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d)
        (p / "w.yml").write_text(text)
        return guard.check(p)


class WorkflowMatrixGuard(unittest.TestCase):
    def test_matrix_with_fail_fast_false_passes(self):
        self.assertEqual(run("jobs:\n  t:\n    strategy:\n      fail-fast: false\n      matrix:\n        a: [1, 2]\n    steps: []\n"), [])

    def test_matrix_without_fail_fast_is_rejected(self):
        self.assertTrue(run("jobs:\n  t:\n    strategy:\n      matrix:\n        a: [1, 2]\n    steps: []\n"))

    def test_fail_fast_true_is_rejected(self):
        self.assertTrue(run("jobs:\n  t:\n    strategy:\n      fail-fast: true\n      matrix:\n        a: [1]\n"))

    def test_strategy_without_matrix_is_ignored(self):
        self.assertEqual(run("jobs:\n  t:\n    strategy:\n      max-parallel: 1\n    steps: []\n"), [])

    def test_fail_fast_in_another_jobs_strategy_does_not_count(self):
        text = ("jobs:\n  a:\n    strategy:\n      fail-fast: false\n      matrix:\n        x: [1]\n"
                "  b:\n    strategy:\n      matrix:\n        y: [1]\n")
        self.assertEqual(len(run(text)), 1)

    def test_dynamic_matrix_expression_still_requires_fail_fast(self):
        self.assertTrue(run("jobs:\n  t:\n    strategy:\n      matrix: ${{ fromJson(needs.p.outputs.m) }}\n"))

    def test_flow_mapping_strategy_without_fail_fast_is_rejected(self):
        self.assertTrue(run("jobs:\n  t:\n    strategy: {matrix: {os: [a, b]}}\n    steps: []\n"))

    def test_flow_mapping_strategy_with_fail_fast_false_passes(self):
        self.assertEqual(run("jobs:\n  t:\n    strategy: {fail-fast: false, matrix: {os: [a, b]}}\n    steps: []\n"), [])

    def test_quoted_or_string_false_is_not_accepted(self):
        self.assertTrue(run("jobs:\n  t:\n    strategy:\n      fail-fast: 'false'\n      matrix:\n        a: [1]\n"))

    def test_whole_strategy_as_an_expression_is_rejected_as_unverifiable(self):
        self.assertTrue(run("jobs:\n  t:\n    strategy: ${{ fromJson(needs.p.outputs.s) }}\n    steps: []\n"))

    def test_unparseable_workflow_fails_closed(self):
        self.assertTrue(run("jobs: [unclosed\n"))

    def test_repository_workflows_comply(self):
        self.assertEqual(guard.check(guard.WORKFLOWS), [])


if __name__ == "__main__":
    unittest.main()
