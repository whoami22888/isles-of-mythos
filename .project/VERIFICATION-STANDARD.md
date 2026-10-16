# Verification and Documentation Standard

## Mandatory current-verification format

Every current verification statement MUST identify:
1. The exact Git commit SHA.
2. The verification date.
3. The workflow/run ID where applicable.
4. The verification status.

Example:

`Verified commit <40-char-SHA> on YYYY-MM-DD: CI #<run> PASS; Performance Acceptance #<run> PASS; Static Security Quality #<run> PASS.`

## SHA validity

- Query GitHub for the authoritative current branch HEAD; never infer it from memory or another document.
- Verification evidence belongs to the exact commit SHA that produced it.
- Any HEAD change invalidates current-head verification claims unless the new exact HEAD is independently verified.
- Historical SHAs may be retained only when explicitly labelled historical/source-state evidence.
- Never label an old SHA as current.
- Never transfer CI, security, performance, audit, or acceptance evidence between SHAs.
- If exact-head evidence is unavailable, status is NOT VERIFIED, not PASS.

## Single implementation owner per task

The Build Controller coordinates one GPT/Codex engineering team. Each task has exactly one implementation owner and non-overlapping write surfaces. The Integration/Auto-Fix Reviewer owns corrections discovered in review or explicitly delegates a specialist; a distinct agent independently reviews the corrected final SHA. GPT-1/GPT-2 ownership, co-ownership, synchronization-lock and veto gates remain retired. Model names do not create separate approval authorities.

Before a material repository change, the task owner records:
- ACTIVE HEAD
- ACTIVE BRANCH
- ACTIVE GATE / WORKSTREAM
- FILES BEING MODIFIED
- LAST VERIFIED CI / SECURITY / PERFORMANCE
- OPEN BLOCKERS

This ownership rule does not waive project controls: exact-SHA CI/security/performance acceptance, audit evidence, frozen Gates 1–16, release controls, and human authorization for protected settings remain in force. Missing, stale, cancelled, skipped, or inconclusive required checks are not PASS.

## Required change record

After a change, the milestone record in Notion (or a repository checkpoint while Notion is unavailable) must include:
- DATE/TIME
- CODE IMPLEMENTATION OWNER (assigned task owner)
- COMMIT
- BRANCH
- FILES CHANGED
- PURPOSE
- ROOT CAUSE
- FIX
- TESTS
- CI
- SECURITY
- PERFORMANCE
- REMAINING RISKS
- NEXT AUTHORIZED ACTION

## Prevention rule for documentation drift

The root cause of SHA drift was allowing an obsolete SHA to remain labelled as a current verification baseline.

Prevention:
- Query current HEAD before documentation updates.
- Label source-state/historical SHAs explicitly.
- Record exact SHA and evidence identifiers.
- Reverify after every HEAD change.
- Read Notion's authoritative baseline before continuing work.
