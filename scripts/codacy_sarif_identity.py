"""Assign explicit identities to Codacy's otherwise anonymous SARIF runs.

Keep the scanner output as evidence; the upload copy differs only in missing
automationDetails.id values. Categories identify a tool's invocation slot, never
a commit, tool version or finding hash (which would create new alerts each run).
"""
import json
import os
import sys
from collections import Counter
from copy import deepcopy
from urllib.parse import quote


def identify_runs(document):
    if document.get("version") != "2.1.0" or not isinstance(document.get("runs"), list):
        raise ValueError("Expected a SARIF 2.1.0 log with runs")
    output = deepcopy(document)
    occurrences = Counter()
    identities = set()
    for run in output["runs"]:
        tool = run["tool"]["driver"]["name"]
        if not isinstance(tool, str) or not tool:
            raise ValueError("Every SARIF run needs a tool name")
        occurrences[tool] += 1
        details = run.setdefault("automationDetails", {})
        if "id" not in details:
            details["id"] = f"codacy/{quote(tool, safe='')}/{occurrences[tool]}/"
        identity = details["id"]
        if not isinstance(identity, str) or not identity:
            raise ValueError("Invalid analysis identity")
        key = (tool, identity)
        if key in identities:
            raise ValueError("Duplicate explicit analysis identity")
        identities.add(key)
    return output


def split_reports(document, max_runs=20):
    """Return lossless SARIF upload parts within GitHub's run limit."""
    if max_runs < 1:
        raise ValueError("max_runs must be positive")
    identified = identify_runs(document)
    runs = identified["runs"]
    return [
        {**identified, "runs": runs[start:start + max_runs]}
        for start in range(0, len(runs), max_runs)
    ]


if __name__ == "__main__":
    source, destination = sys.argv[1:]
    if source == destination:
        raise ValueError("Preserve the original scanner output")
    with open(source, encoding="utf-8") as stream:
        reports = split_reports(json.load(stream))
    os.makedirs(destination, exist_ok=False)
    for index, report in enumerate(reports, start=1):
        with open(os.path.join(destination, f"part-{index:02d}.sarif"), "x", encoding="utf-8") as stream:
            json.dump(report, stream)
            stream.write("\n")
