# Shops, Resources, Upgrades and Defences

## Design

Players can spend server-authoritative Gold Doubloons at persistent shops for:

- resources
- camp upgrades
- storage/production upgrades
- defensive structures

The shop catalogue is data-driven and lives on the server. The client must never be trusted to supply prices.

## Current catalogue

### Resources

- Wood Bundle
- Stone Bundle
- Iron Ore Bundle
- Herb Bundle

### Upgrades

- Camp Tier II
- Storage Tier II
- Forge Tier II

### Defences

- Defensive Wall Segment
- Defensive Cannon
- Watchtower

## Transaction rules

A purchase must:

1. authenticate the player;
2. validate the shop item against the server catalogue;
3. validate quantity and purchase limits;
4. calculate the price server-side;
5. atomically deduct Gold Doubloons;
6. atomically grant the purchased item to the persistent inventory;
7. commit both changes together;
8. return the updated authoritative player state.

The client may optimistically update shop UI, but the server is authoritative and can reject/rollback the operation.

## Future shop expansion

The same system will support:

- ship parts
- ammunition
- tools
- crafting stations
- creature food
- capture equipment
- rare materials
- cosmetic items
- guild supplies
- siege equipment
- territory supplies

Shop stock, regional availability and dynamic pricing can later be layered on without changing the client purchase contract.
