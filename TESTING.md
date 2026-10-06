# Testing

## Required gate
A phase is not verified until migrations, lint, client typecheck, server typecheck, client tests, server tests, production build, and cleanup all pass.

## Debugging procedure
Use BUILD -> TEST -> INSPECT -> FIX -> RETEST -> VERIFY -> DOCUMENT -> CONTINUE. For every failure record the exact failure, location, root cause, why, fix, regression risk, and evidence.

## Anti-loop rule
Do not repeatedly rerun the same failure. Every retry requires a new root-cause hypothesis or a targeted correction. Never increase a timeout merely to hide an unresolved synchronization or logic defect.

## Phase 5 coverage
Creature verification covers authoritative combat damage, capture threshold and item consumption, owned-creature persistence, taming, party assignment, AI mode changes, disconnect persistence, and cross-account capture ownership protection.

## Evidence
Passing tests prove only the behaviours they exercise. Untested functionality remains unverified.
