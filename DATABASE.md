# Database

## Current storage
PostgreSQL is the persistent store and node-pg-migrate applies schema changes.

## Persistent domains
The schema covers users/player profiles, creatures, bases, crafting/economy, breeding, ships/fleets, guilds, armies, realms/territories, invasions, social/auction systems, world events, endgame warfare, mythic content and territory seasons.

## Consistency
Important mutations use PostgreSQL transactions and row/advisory locks. Currency and inventory operations are server-authoritative. Creature ownership uses a global unique wild-source constraint. Revision tracking protects asynchronous persistence from clearing newer in-memory mutations.

## Endgame persistence
Realm wars, guild battles, endgame creatures, mythic content and territory seasons are represented by dedicated migrations and server-side stores. Scores, contributions, rewards and season standings are persisted in PostgreSQL.

## Migrations
Migrations are forward-only project history and are exercised in CI. Historical CI #858 successfully applied migrations and completed PostgreSQL backup/restore verification on its original workflow commit; that historical result must not be treated as current-main evidence.

Current main HEAD is `83e4c14b94861c0585c1a50993f7297ad0dda497`, verified from GitHub on 2026-10-08.