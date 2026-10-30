#!/usr/bin/env python3
"""Every GitHub Actions job that uses a matrix must set `fail-fast: false` so one failing leg cannot cancel the
other legs and hide their diagnostics (IOM-00). Workflows are parsed as YAML, so block and flow mappings are
treated alike; a strategy that cannot be verified (an expression, unparseable YAML) fails closed."""
import pathlib
import sys

try:
    import yaml
except ImportError:  # fail closed rather than silently accepting everything
    print("Workflow matrix guard FAIL: PyYAML is required (pip install pyyaml)")
    sys.exit(1)

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"


def check(directory=WORKFLOWS):
    problems = []
    for path in sorted(pathlib.Path(directory).glob("*.y*ml")):
        try:
            document = yaml.safe_load(path.read_text())
        except yaml.YAMLError as error:
            problems.append(f"{path.name}: cannot parse workflow YAML ({str(error).splitlines()[0]})")
            continue
        jobs = document.get("jobs") if isinstance(document, dict) else None
        if not isinstance(jobs, dict):
            continue
        for name, job in jobs.items():
            strategy = job.get("strategy") if isinstance(job, dict) else None
            if strategy is None:
                continue
            if not isinstance(strategy, dict):
                problems.append(f"{path.name}: job `{name}` strategy is not a mapping (an expression cannot be verified)")
            elif "matrix" in strategy and strategy.get("fail-fast") is not False:
                problems.append(f"{path.name}: job `{name}` matrix must set exactly `fail-fast: false` "
                                f"(found {strategy.get('fail-fast', 'none')!r})")
    return problems


if __name__ == "__main__":
    found = check()
    if found:
        print("Workflow matrix guard FAIL:\n" + "\n".join(f" - {p}" for p in found))
        sys.exit(1)
    print("Workflow matrix guard PASS")
