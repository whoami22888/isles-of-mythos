import unittest
from copy import deepcopy
from codacy_sarif_identity import identify_runs


class SarifIdentityTests(unittest.TestCase):
    def test_preserves_every_run_finding_and_metadata(self):
        runs = [
            {"tool": {"driver": {"name": "ESLint", "version": "9"}},
             "results": [{"ruleId": "security", "level": "error"}],
             "invocations": [{"executionSuccessful": False}]},
            {"tool": {"driver": {"name": "ESLint", "version": "9"}}, "results": []},
        ]
        source = {"version": "2.1.0", "runs": runs}
        original = deepcopy(source)
        result = identify_runs(source)
        self.assertEqual(source, original)
        self.assertEqual(len(result["runs"]), 2)
        self.assertEqual(len({r["automationDetails"]["id"] for r in result["runs"]}), 2)
        for run in result["runs"]:
            del run["automationDetails"]
        self.assertEqual(result, original)

    def test_existing_identity_and_metadata_are_preserved_and_idempotent(self):
        source = {"version": "2.1.0", "runs": [
            {"tool": {"driver": {"name": "Lint"}},
             "automationDetails": {"id": "owned/language/", "description": {"text": "keep"}}}]}
        self.assertEqual(identify_runs(source), source)
        self.assertEqual(identify_runs(identify_runs(source)), source)

    def test_findings_versions_and_other_tools_do_not_change_identity(self):
        first = {"tool": {"driver": {"name": "Lint", "version": "1"}}, "results": []}
        changed = deepcopy(first)
        changed["tool"]["driver"]["version"] = "2"
        changed["results"] = [{"ruleId": "new-finding"}]
        a = identify_runs({"version": "2.1.0", "runs": [first]})
        b = identify_runs({"version": "2.1.0", "runs": [
            {"tool": {"driver": {"name": "Other"}}}, changed]})
        self.assertEqual(a["runs"][0]["automationDetails"], b["runs"][1]["automationDetails"])

    def test_duplicate_existing_ids_fail_without_discarding_runs(self):
        run = {"tool": {"driver": {"name": "Lint"}}, "automationDetails": {"id": "same/"}}
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            identify_runs({"version": "2.1.0", "runs": [run, deepcopy(run)]})

    def test_tool_names_are_encoded_without_slug_collisions(self):
        output = identify_runs({"version": "2.1.0", "runs": [
            {"tool": {"driver": {"name": name}}} for name in ["a/b", "a b", "a-b"]]})
        self.assertEqual(len({r["automationDetails"]["id"] for r in output["runs"]}), 3)


if __name__ == "__main__":
    unittest.main()
