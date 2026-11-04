"""Fail closed on incomplete Trivy SARIF and bind evidence to the checked-out SHA."""

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


def validate_report(document: object) -> None:
    """Require one complete Trivy SARIF run without external result files."""
    if not isinstance(document, dict) or document.get("version") != "2.1.0":
        raise ValueError("Trivy must produce SARIF 2.1.0")
    if document.get("externalPropertyFileReferences"):
        raise ValueError("External SARIF properties are not retained")
    runs = document.get("runs")
    if not isinstance(runs, list) or len(runs) != 1:
        raise ValueError("Expected one Trivy run")
    run = runs[0]
    if not isinstance(run, dict) or run.get("externalPropertyFileReferences"):
        raise ValueError("Trivy run is incomplete")
    tool = run.get("tool")
    driver = tool.get("driver") if isinstance(tool, dict) else None
    if not isinstance(driver, dict) or driver.get("name") != "Trivy":
        raise ValueError("Unexpected SARIF tool")
    if not isinstance(run.get("results"), list):
        raise ValueError("Trivy results are missing")
    for result in run["results"]:
        if not isinstance(result, dict):
            raise ValueError("Malformed Trivy result")
    for invocation in run.get("invocations", []):
        if not isinstance(invocation, dict) or invocation.get("executionSuccessful") is False:
            raise ValueError("Trivy invocation failed")


def validate_source_sha(expected: str, actual: str) -> None:
    """Reject stale or malformed source identities."""
    if not re.fullmatch(r"[0-9a-f]{40}", expected) or actual != expected:
        raise ValueError("Trivy source SHA differs from checkout")


def main(report_path: Path, expected_sha: str, receipt_path: Path) -> None:
    """Validate source and report, then write a hash receipt for the raw SARIF."""
    actual_sha = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], text=True, encoding="utf-8"
    ).strip()
    validate_source_sha(expected_sha, actual_sha)
    raw = report_path.read_bytes()
    validate_report(json.loads(raw))
    receipt = {"source_sha": actual_sha, "sarif_sha256": hashlib.sha256(raw).hexdigest()}
    receipt_path.write_text(json.dumps(receipt, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main(Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]))
