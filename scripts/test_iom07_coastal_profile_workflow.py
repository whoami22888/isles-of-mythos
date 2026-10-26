"""Regression checks for the coastal profiler's GitHub Actions path filter."""

import re
import unittest
from pathlib import Path


WORKFLOW = (
    Path(__file__).resolve().parents[1]
    / ".github"
    / "workflows"
    / "iom07-moving-coastal-profile.yml"
)
REQUIRED_PULL_REQUEST_PATHS = {
    "client-godot/shaders/coastal_shore_sampler.gdshaderinc",
    "client-godot/scripts/coastal_shore_heightfield.gd",
    "client-godot/tests/coastal_shore_heightfield_test.gd",
    "client-godot/tests/coastal_ocean_integration_test.gd",
    "client-godot/tests/coastal_ship_fx_integration_test.gd",
    "scripts/test_iom07_coastal_profile_workflow.py",
}


def pull_request_paths(workflow_text: str) -> set[str]:
    """Return only path entries nested under the workflow's pull_request key."""
    lines = workflow_text.splitlines()
    try:
        section_start = next(
            index
            for index, line in enumerate(lines)
            if re.fullmatch(r"  pull_request:", line)
        )
    except StopIteration:
        return set()

    paths: set[str] = set()
    in_paths = False
    for line in lines[section_start + 1 :]:
        indent = len(line) - len(line.lstrip(" "))
        if line and indent <= 2:
            break
        if indent == 4 and line.strip() == "paths:":
            in_paths = True
            continue
        if in_paths and indent == 4:
            break
        if in_paths:
            match = re.fullmatch(r'      - "([^\"]+)"', line)
            if match:
                paths.add(match.group(1))
    return paths


class CoastalProfilerWorkflowTest(unittest.TestCase):
    """Ensure profiler-gated scene inputs always schedule the profiler."""

    def test_all_protected_coastal_inputs_trigger_pull_request_profile(self):
        paths = pull_request_paths(WORKFLOW.read_text(encoding="utf-8"))
        self.assertTrue(
            REQUIRED_PULL_REQUEST_PATHS.issubset(paths),
            f"Missing pull_request path triggers: {sorted(REQUIRED_PULL_REQUEST_PATHS - paths)}",
        )


if __name__ == "__main__":
    unittest.main()
