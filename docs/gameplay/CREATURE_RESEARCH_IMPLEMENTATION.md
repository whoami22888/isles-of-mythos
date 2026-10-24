# IOM-04 creature research and training — staged implementation

Status: **policy module only; no playable unlock/flight system is claimed**.

Design authority: full-game-prompt.PDF; Commercial Production Control Centre / Build Instructions, 2026-10-18 clarification; issue #169; repository AGENTS.md. Isles of Mythos is a mobile-first strategy MMORPG, not merely a pirate combat game.

## First isolated server policy slice

`server/src/creature-mastery.ts` contains explicit player research prerequisites, active building-level gates, rank thresholds, controlled server-awarded practice bounds and independent tame/creature-command capability checks. Tests cover hidden/locked research, disabled facilities, player/creature XP separation, impossible flight capabilities and overlapping worker/combat/mount/breeding assignments.

This code intentionally has **no client/API entrypoint, migrations, paid unlock, randomized treasure, flight simulation, fabricated assets or direct gameplay mutation**. It is a prerequisite validation library, not a substitute for enforced backend state. It does not change existing Gate 5/6/8 capture formula, active workers or protected database migrations.

## Follow-on dependency-gated work (NOT VERIFIED)

1. Bind prerequisites to live BaseStore buildings, player research inventory and verified quest/research discovery. Implement a new *reviewed* progression migration and transactional research unlocks; enforce immutable event identifiers and atomic earned-resource deductions.
2. Persist separate player skill XP and per-creature bond, XP and taught commands in PostgreSQL. Only server-resolved successful practice may award capped XP, never client amounts or duplicate event IDs.
3. Attach checks to server-authoritative command/worker/army/ride/fly boundaries, including species capability tables, job exclusivity, stamina, ownership and offline/reconnect reconciliation. The pure function alone does not enforce network authority.
4. Provide Godot 4.7.2 Android touch UI, visible research/tree/training affordances and physical-device performance verification. Visual output must meet the owner's cinematic quality floor; do not claim visual compliance from code tests.
5. Verify Build & Integrity, Functionality & Integration, Data & Transaction Safety at exact PR SHA (including mandatory CI/security/performance and independent GPT review) before integration.

Balanced costs, research sources and rank rewards require economy/design review before production binding. Never replace legitimate XP with purchases or prevent earnable advancement.
