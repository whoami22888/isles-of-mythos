"""Negative regression tests for the Trivy evidence admission gate."""

import unittest
from copy import deepcopy

from validate_trivy_sarif import validate_report, validate_source_sha


GOOD = {"version": "2.1.0", "runs": [
    {"tool": {"driver": {"name": "Trivy"}}, "results": []}
]}


class TrivySarifTests(unittest.TestCase):
    """Check source and report failures before SARIF upload."""

    def test_accepts_complete_empty_report(self):
        """A clean scan may contain zero findings."""
        validate_report(GOOD)

    def test_rejects_missing_or_wrong_tool_and_results(self):
        """Other tools and absent results cannot impersonate Trivy."""
        for report in ({}, {"version": "2.1.0", "runs": []},
                       {"version": "2.1.0", "runs": [{}]}):
            with self.assertRaises(ValueError):
                validate_report(report)
        for key, value in (("name", "Other"), ("name", "")):
            report = deepcopy(GOOD)
            report["runs"][0]["tool"]["driver"][key] = value
            with self.assertRaises(ValueError):
                validate_report(report)
        report = deepcopy(GOOD)
        del report["runs"][0]["results"]
        with self.assertRaises(ValueError):
            validate_report(report)

    def test_rejects_external_or_failed_content(self):
        """Partial external reports and failed invocations cannot pass."""
        for scope in ("document", "run"):
            report = deepcopy(GOOD)
            target = report if scope == "document" else report["runs"][0]
            target["externalPropertyFileReferences"] = {"results": []}
            with self.assertRaises(ValueError):
                validate_report(report)
        report = deepcopy(GOOD)
        report["runs"][0]["invocations"] = [{"executionSuccessful": False}]
        with self.assertRaises(ValueError):
            validate_report(report)

    def test_rejects_stale_source_sha(self):
        """Only a 40-character SHA matching HEAD binds the report."""
        sha = "a" * 40
        validate_source_sha(sha, sha)
        for expected, actual in ((sha, "b" * 40), ("short", "short")):
            with self.assertRaises(ValueError):
                validate_source_sha(expected, actual)


if __name__ == "__main__":
    unittest.main()
