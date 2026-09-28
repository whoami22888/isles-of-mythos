# Database

## Current storage
PostgreSQL is the persistent store and node-pg-migrate applies schema changes.

## Key entities
- `users` and `player_profiles` store account/player state.
- `player_creatures` stores owned creature state.
- `wild_source_id` has a global unique index to prevent one world spawn being owned by multiple accounts.

## Creature persistence
Owned creatures store identity, owner, wild source, species, level/XP, health, combat stats, element, abilities, tame progress, party slot, AI mode, coordinates, and timestamps.

## Consistency
Important creature inventory operations use PostgreSQL transactions and row locks. Revision tracking prevents asynchronous persistence from clearing newer in-memory mutations.

## Migrations
Migration 006 creates the creature schema and backfills creature starter inventory keys for existing players without overwriting existing inventory values. Migration 007 enforces global wild-spawn ownership.
