#!/usr/bin/env python3
"""Every GitHub Actions job that uses a matrix must set `fail-fast: false` so one failing leg cannot cancel the
other legs and hide their diagnostics (IOM-00). Indentation-based so it needs no YAML dependency."""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"


def _indent(line):
    return len(line) - len(line.lstrip(" "))


def check(directory=WORKFLOWS):
    problems = []
    for path in sorted(pathlib.Path(directory).glob("*.y*ml")):
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            if not re.match(r"^\s*strategy:\s*(#.*)?$", line):
                continue
            base = _indent(line)
            block = []
            for nxt in lines[i + 1:]:
                if nxt.strip() and not nxt.lstrip().startswith("#") and _indent(nxt) <= base:
                    break
                block.append(nxt)
            if not any(re.match(r"^\s*matrix:", b) for b in block):
                continue
            values = [m.group(1).lower() for b in block if (m := re.match(r"^\s*fail-fast:\s*(\S+)", b))]
            if values != ["false"]:
                problems.append(f"{path.name}:{i + 1}: matrix job must set exactly `fail-fast: false` (found {values or 'none'})")
    return problems


if __name__ == "__main__":
    found = check()
    if found:
        print("Workflow matrix guard FAIL:\n" + "\n".join(f" - {p}" for p in found))
        sys.exit(1)
    print("Workflow matrix guard PASS")
