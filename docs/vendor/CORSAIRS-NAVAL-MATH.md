# Corsairs naval-math source admission

- Upstream repository: [Elkhan-Isayev/corsairs](https://github.com/Elkhan-Isayev/corsairs)
- Immutable upstream commit:
  `22467f438be328924e6abf0578e970943eb0fd88`
  (committed 2026-10-07).
- Licence: MIT. The exact upstream `LICENSE` is copied to
  `LICENSES/MIT-Corsairs.txt`.
- Imported source files:
  - `core/sailing.gd`
  - `core/combat.gd`
  - `core/ammo.gd`
  - `core/ship.gd`
  - `core/ship_types.gd`
  - `core/boarding.gd`
- Every imported file is pinned by its SHA-256 content hash and the same
  immutable upstream commit revision in `vendor.lock.json`.

This is a source-only reference admission. It is not wired into the live game
or authoritative server. The sailing and combat helpers accept an injected
`RandomNumberGenerator`; deterministic replay still requires the caller to
seed it from authoritative server state and preserve call order. No production
simulation or performance claim is made by this import.
