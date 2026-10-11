# Testing

## Required verification chain
A phase is not verified until migrations, lint, typecheck, tests, production build and cleanup pass, with security/performance evidence where required.

## Debugging procedure
Use BUILD -> TEST -> INSPECT -> FIX -> RETEST -> VERIFY -> DOCUMENT -> CONTINUE. For every failure record exact failure, location, root cause, contributing factor, fix, regression risk and evidence.

## Anti-loop rule
Do not repeatedly rerun the same failure. Every retry requires new evidence or a targeted correction. Never increase a timeout merely to hide an unresolved synchronization or logic defect.

## Current acceptance
Verified on 2026-10-10 at main SHA `30eef8b10d80363dc15b4256362d45b6b669019a`:
- CI #1128 / run [38055682984](https://github.com/whoami22888/isles-of-mythos/actions/runs/38055682984) — PASS.
- Performance Acceptance #345 / run [38055682961](https://github.com/whoami22888/isles-of-mythos/actions/runs/38055682961) — PASS.
- Static Security Quality #317 / run [38055682968](https://github.com/whoami22888/isles-of-mythos/actions/runs/38055682968) — PASS.
## Evidence rule
Passing tests prove only the behaviours they exercise. PDF post-Phase-16 architecture, scaling, mobile/GPU and production requirements remain separately classified until direct evidence exists.