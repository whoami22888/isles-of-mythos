# Isles of Mythos agent guide

This file is a navigation layer. The linked project documents remain authoritative; do not copy their historical verification records into new claims.

## Read before editing

1. `full-game-prompt.PDF` (requirements source when available in the task context).
2. `.project/VERIFICATION-STANDARD.md` (exact-SHA evidence and change-record rules).
3. `CONTRIBUTING.md` and `TESTING.md` (scope, test order, and anti-loop rules).
4. The current Notion Master Project Index and live GitHub state (current decisions, branch/PR HEADs, checks, reviews).

Gates 1–16 and any explicit Step 5 blocker remain frozen unless the owner authorizes a change.

## Before a change

- Query live `main`, relevant PR HEADs, checks, reviews, and mergeability. Do not infer current state from README or Notion history.
- Inspect `git status` and keep imported or user-dirty checkouts untouched; use an isolated worktree for implementation.
- Claim one non-overlapping workstream and file set. One implementation owner is sufficient; independent review verifies the result. Do not add a second-owner or duplicate approval gate.
- Reuse test evidence only when the exact commit SHA is unchanged. Any new commit requires fresh exact-SHA evidence.

## Verification

Use the smallest useful loop: targeted tests → affected server/client tests → typecheck → lint → build. For a final PR HEAD, require the configured exact-SHA CI, security, performance, and independent-review gates. Record failures as evidence with root cause, bounded correction, and prevention lesson; do not weaken thresholds, tests, timeouts, or acceptance criteria.

Keep gameplay authority, transaction/idempotency guarantees, replay protections, and privacy boundaries intact. Diagnostic logs must not contain player, request, inventory, credential, or other sensitive identifiers.

## Reporting

Every material change record includes exact SHA, branch, files, purpose, root cause, fix, tests, exact workflow IDs/statuses, review status, risks, blockers, and next action. Update and read back the Notion checkpoint after implementation or verification changes.

## Model and task settings

Use the model/task options exposed by the current Codex environment only when needed. Do not assume aliases, pricing, quota limits, or unsupported `/model` settings. Keep delegated contexts bounded and avoid duplicate work; routine read-only checks can use a lower-cost option only when the environment explicitly exposes and authorizes one.
