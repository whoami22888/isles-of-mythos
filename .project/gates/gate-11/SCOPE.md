# Gate 11 — Tactical Armies

Status: VERIFIED / FROZEN pending final documentation CI.

Authoritative Phase 11 scope:
- Barracks
- Garrison
- Army composition
- Command system
- Tactical combat
- Defensive structures

Implemented:
- Persistent player armies and server-authoritative army assignments.
- Barracks-gated timestamp-based training queues.
- Infantry, magical, creature and siege unit composition.
- Creature-to-army assignment with ownership/taming/party protections.
- Garrison persistence and army assignments for base defense, patrol, expedition, resource protection, guild mission, realm warfare, invasion, convoy and naval operations.
- Persistent formations.
- Guild commander nominations and army commander assignment.
- Logged commander orders, including movement, attack, defense, retreat, rally, reinforcement, hold, focus-fire and map-marker payloads.
- Server-authoritative tactical battle instances with persistent deployed battle units and turn resolution.
- Tactical abilities, retreat, cannon/siege actions, traps and reinforcement actions.
- Persistent defensive structures covering towers, walls, gates and traps.
- Transactional resource deduction for training and defensive construction.
- Restart-safe state stored in PostgreSQL rather than client state.
