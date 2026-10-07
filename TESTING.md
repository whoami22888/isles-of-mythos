# Testing

## Required verification chain
A phase is not verified until migrations, lint, typecheck, tests, production build and cleanup pass, with security/performance evidence where required.

## Debugging procedure
Use BUILD -> TEST -> INSPECT -> FIX -> RETEST -> VERIFY -> DOCUMENT -> CONTINUE. For every failure record exact failure, location, root cause, contributing factor, fix, regression risk and evidence.

## Anti-loop rule
Do not repeatedly rerun the same failure. Every retry requires new evidence or a targeted correction. Never increase a timeout merely to hide an unresolved synchronization or logic defect.

## Current acceptance
The current main Phase 16 baseline passed:
- CI #858: migrations, audit, lint/typecheck, full test suite, build, Docker Compose validation, backup/restore and production image.
- Performance Acceptance #78: 1,000-player seeded sustained-load scenario with host/PostgreSQL metrics capture.
- Static Security #50.

## Evidence rule
Passing tests prove only the behaviours they exercise. PDF post-Phase-16 architecture, scaling, mobile/GPU and production requirements remain separately classified until direct evidence exists.