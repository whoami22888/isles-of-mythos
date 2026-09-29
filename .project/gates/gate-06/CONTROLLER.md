# Gate 6 Controller Protocol

The controller owns orchestration and final accountability.

## Before implementation
- Read the complete Gate 6 specification and relevant detailed PDF sections.
- Inspect repository state at the Gate 5 frozen baseline.
- Build/update the block dependency graph.
- Assign exactly one specialist role per block.
- Maintain LEDGER.md continuously.

## During implementation
- Allow parallel work only when ownership and dependencies are safe.
- Prevent scope creep and duplicate work.
- Reopen only the affected block after a failure whenever possible.
- Keep a deferred-findings list for work outside Phase 6.

## Final audit
The controller independently reviews the combined implementation against every Gate 6 requirement, checks tests and CI evidence, inspects changed files, and determines PASS/REOPEN. A green CI result alone is insufficient.

## Accountability
No claim of completion is accepted without evidence. The controller is responsible for catching omissions, regressions, unsupported assumptions, and block-boundary failures.
