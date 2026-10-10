import Phaser from "phaser";

export const CHUNK_SIZE = 32;
export const TILE_SIZE = 32;

export enum TileKind {
  Ocean = 0,
  Shallow = 1,
  Sand = 2,
  Grass = 3,
  Rock = 4,
  Reef = 5,
}

export interface ResourceNode {
  id: string;
  type: "wood" | "stone" | "herb";
  x: number;
  y: number;
}

export interface CreatureSpawn {
  id: string;
  species: "slime" | "boar" | "raptor";
  x: number;
  y: number;
  level: number;
}

export interface ResourceMillSpawn {
  id: string;
  x: number;
  y: number;
  level: 7;
}

export interface WorldChunk {
  x: number;
  y: number;
  size: number;
  tiles: number[];
  resources?: ResourceNode[];
  creatures?: CreatureSpawn[];
  resourceMillSpawns?: ResourceMillSpawn[];
}

const TILE_COLORS: Record<number, number> = {
  [TileKind.Ocean]: 0x123b62,
  [TileKind.Shallow]: 0x1c6680,
  [TileKind.Sand]: 0xd5bc76,
  [TileKind.Grass]: 0x3d7b49,
  [TileKind.Rock]: 0x5c6470,
  [TileKind.Reef]: 0x2b8a83,
};

interface ChunkRenderLayers {
  terrain: Phaser.GameObjects.Graphics;
  entities: Phaser.GameObjects.Graphics;
  resourceIds: Set<string>;
  creatureIds: Set<string>;
  resourceMillIds: Set<string>;
}

interface IndexedResource {
  node: ResourceNode;
  chunkKey: string;
}

interface IndexedCreature {
  spawn: CreatureSpawn;
  chunkKey: string;
}

interface IndexedResourceMill {
  spawn: ResourceMillSpawn;
  chunkKey: string;
}

/**
 * Keeps the terrain and entity marker layers batched per chunk.
 * Entity positions are indexed separately from Phaser objects so proximity
 * queries do not depend on render-object coordinates.
 */
export class ChunkRenderer {
  private readonly chunks = new Map<string, ChunkRenderLayers>();
  private readonly creatures = new Map<string, IndexedCreature>();
  private readonly resources = new Map<string, IndexedResource>();
  private readonly resourceMills = new Map<string, IndexedResourceMill>();

  constructor(private readonly scene: Phaser.Scene) {}

  render(chunk: WorldChunk): void {
    const key = `${chunk.x},${chunk.y}`;
    if (this.chunks.has(key)) return;

    const terrain = this.scene.add.graphics();
    const entities = this.scene.add.graphics();
    const layers: ChunkRenderLayers = {
      terrain,
      entities,
      resourceIds: new Set<string>(),
      creatureIds: new Set<string>(),
      resourceMillIds: new Set<string>(),
    };
    const originX = chunk.x * chunk.size * TILE_SIZE;
    const originY = chunk.y * chunk.size * TILE_SIZE;

    for (let y = 0; y < chunk.size; y += 1) {
      let currentKind = -1;
      for (let x = 0; x < chunk.size; x += 1) {
        const kind = chunk.tiles[y * chunk.size + x] ?? TileKind.Ocean;
        if (kind !== currentKind) {
          terrain.fillStyle(TILE_COLORS[kind] ?? TILE_COLORS[TileKind.Ocean], 1);
          currentKind = kind;
        }
        terrain.fillRect(
          originX + x * TILE_SIZE,
          originY + y * TILE_SIZE,
          TILE_SIZE + 1,
          TILE_SIZE + 1,
        );
      }
    }

    terrain.setDepth(-100);
    entities.setDepth(10);
    this.chunks.set(key, layers);

    for (const resource of chunk.resources ?? []) {
      if (this.resources.has(resource.id)) continue;
      this.resources.set(resource.id, { node: resource, chunkKey: key });
      layers.resourceIds.add(resource.id);
    }

    for (const creature of chunk.creatures ?? []) {
      if (this.creatures.has(creature.id)) continue;
      this.creatures.set(creature.id, { spawn: creature, chunkKey: key });
      layers.creatureIds.add(creature.id);
    }

    for (const spawn of chunk.resourceMillSpawns ?? []) {
      if (this.resourceMills.has(spawn.id)) continue;
      this.resourceMills.set(spawn.id, { spawn, chunkKey: key });
      layers.resourceMillIds.add(spawn.id);
    }

    this.redrawEntities(layers);
  }

  unloadOutside(radius: number, centerChunkX: number, centerChunkY: number): void {
    for (const [key, layers] of this.chunks) {
      const [x, y] = key.split(",").map(Number);
      if (Math.abs(x - centerChunkX) <= radius && Math.abs(y - centerChunkY) <= radius) continue;

      layers.terrain.destroy();
      layers.entities.destroy();
      this.chunks.delete(key);
      for (const resourceId of layers.resourceIds) this.resources.delete(resourceId);
      for (const creatureId of layers.creatureIds) this.creatures.delete(creatureId);
      for (const spawnId of layers.resourceMillIds) this.resourceMills.delete(spawnId);
    }
  }

  removeResource(id: string): void {
    const resource = this.resources.get(id);
    if (!resource) return;
    this.resources.delete(id);
    const layers = this.chunks.get(resource.chunkKey);
    if (!layers) return;
    layers.resourceIds.delete(id);
    this.redrawEntities(layers);
  }

  nearestResource(x: number, y: number, maxDistance = 2.5): ResourceNode | null {
    let nearest: ResourceNode | null = null;
    let nearestDistance = maxDistance;
    for (const { node } of this.resources.values()) {
      const distance = Math.hypot(node.x - x, node.y - y);
      if (distance < nearestDistance) {
        nearest = node;
        nearestDistance = distance;
      }
    }
    return nearest ? { ...nearest } : null;
  }

  removeCreature(id: string): void {
    const creature = this.creatures.get(id);
    if (!creature) return;
    this.creatures.delete(id);
    const layers = this.chunks.get(creature.chunkKey);
    if (!layers) return;
    layers.creatureIds.delete(id);
    this.redrawEntities(layers);
  }

  get loadedCount(): number {
    return this.chunks.size;
  }

  nearestCreature(x: number, y: number, maxDistance = 10): { id: string; x: number; y: number } | null {
    let nearest: { id: string; x: number; y: number } | null = null;
    let nearestDistance = maxDistance;
    for (const [id, { spawn }] of this.creatures) {
      const distance = Math.hypot(spawn.x - x, spawn.y - y);
      if (distance < nearestDistance) {
        nearest = { id, x: spawn.x, y: spawn.y };
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  private redrawEntities(layers: ChunkRenderLayers): void {
    layers.entities.clear();
    for (const id of layers.resourceIds) {
      const indexed = this.resources.get(id);
      if (!indexed) continue;
      const resource = indexed.node;
      const color = resource.type === "wood" ? 0x8b6f47 : resource.type === "stone" ? 0x9aa0a6 : 0x76b852;
      const x = resource.x * TILE_SIZE + TILE_SIZE / 2;
      const y = resource.y * TILE_SIZE + TILE_SIZE / 2;
      layers.entities.fillStyle(color, 1);
      layers.entities.fillCircle(x, y, TILE_SIZE * 0.2);
      layers.entities.lineStyle(1, 0xffffff, 0.75);
      layers.entities.strokeCircle(x, y, TILE_SIZE * 0.24);
    }
    for (const id of layers.creatureIds) {
      const indexed = this.creatures.get(id);
      if (!indexed) continue;
      const creature = indexed.spawn;
      const color = creature.species === "raptor" ? 0xd95f59 : creature.species === "boar" ? 0x8b6f47 : 0x6bcf63;
      const x = creature.x * TILE_SIZE + TILE_SIZE / 2;
      const y = creature.y * TILE_SIZE + TILE_SIZE / 2;
      layers.entities.fillStyle(color, 1);
      layers.entities.fillCircle(x, y, TILE_SIZE * 0.25);
      layers.entities.lineStyle(1, 0xffffff, 0.8);
      layers.entities.strokeCircle(x, y, TILE_SIZE * 0.28);
    }
    for (const id of layers.resourceMillIds) {
      const indexed = this.resourceMills.get(id);
      if (!indexed) continue;
      const spawn = indexed.spawn;
      const x = spawn.x * TILE_SIZE + TILE_SIZE / 2;
      const y = spawn.y * TILE_SIZE + TILE_SIZE / 2;
      layers.entities.fillStyle(0xf4c95d, 1);
      layers.entities.fillRect(x - 8, y - 8, 16, 16);
      layers.entities.lineStyle(2, 0x6b4f16, 1);
      layers.entities.strokeCircle(x, y, 12);
    }
  }
}
