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

## Two-GPT synchronization lock

Before repository modification, both GPTs must reconcile:
- ACTIVE HEAD
- ACTIVE BRANCH
- ACTIVE GATE
- ACTIVE WORKSTREAM
- WORK OWNER
- LAST VERIFIED CI
- LAST VERIFIED SECURITY
- LAST VERIFIED PERFORMANCE
- OPEN BLOCKERS
- FILES BEING MODIFIED

One GPT owns a workstream/file set at a time. The other audits or verifies and does not duplicate the implementation. Ownership ambiguity requires a stop and reconciliation through Notion.

## Required change record

After a change, Notion must record:
- DATE/TIME
- GPT OWNER
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
