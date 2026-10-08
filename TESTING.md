# Testing

## Required verification chain
A phase is not verified until migrations, lint, typecheck, tests, production build and cleanup pass, with security/performance evidence where required.

## Debugging procedure
Use BUILD -> TEST -> INSPECT -> FIX -> RETEST -> VERIFY -> DOCUMENT -> CONTINUE. For every failure record exact failure, location, root cause, contributing factor, fix, regression risk and evidence.

## Anti-loop rule
Do not repeatedly rerun the same failure. Every retry requires new evidence or a targeted correction. Never increase a timeout merely to hide an unresolved synchronization or logic defect.

## Current acceptance
Current main is `83e4c14b94861c0585c1a50993f7297ad0dda497`, verified from the GitHub `main` ref on 2026-10-08.

No current-head PASS is claimed here for CI, Performance Acceptance or Static Security until workflow runs are tied directly to this exact SHA. Historical workflow results must remain explicitly historical.

## Evidence rule
Passing tests prove only the behaviours they exercise. PDF post-Phase-16 architecture, scaling, mobile/GPU and production requirements remain separately classified until direct evidence exists.

## Verification documentation standard
Every current verification statement MUST identify the exact Git commit SHA, verification date, workflow/run ID where applicable, and verification status. Changing HEAD invalidates current-head workflow claims until fresh evidence is obtained.