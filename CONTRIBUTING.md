# Contributing

## Workflow
Work only against the active phase branch. Keep changes scoped to the current gate and do not alter frozen phases without reproducible evidence or an explicit scope change.

Before verification:
- inspect changed code and callers;
- run targeted tests for changed behaviour;
- run the complete CI gate;
- document material findings and fixes.

## Code quality
No placeholder implementations, silent error suppression, hard-coded fake outcomes, or TODO-based substitutes for required functionality. Prefer typed inputs, bounded state, transactional writes, and explicit failure handling.

## Review
Use CI and available automated code review as independent evidence. Review findings are leads to investigate, not proof of correctness by themselves.
