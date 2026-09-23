export const CHUNK_SIZE = 32;
export const WORLD_SEED = 137042;

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

export interface WorldChunk {
  x: number;
  y: number;
  size: number;
  tiles: number[];
  resources: ResourceNode[];
  creatures: CreatureSpawn[];
}

function hash(x: number, y: number, seed: number): number {
  let value = Math.imul(x, 374761393) ^ Math.imul(y, 668265263) ^ seed;
  value = Math.imul(value ^ (value >>> 13), 1274126177);
  return ((value ^ (value >>> 16)) >>> 0) / 4294967295;
}

function smooth(value: number): number {
  return value * value * (3 - 2 * value);
}

function valueNoise(x: number, y: number, seed: number): number {
  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const tx = smooth(x - x0);
  const ty = smooth(y - y0);

  const a = hash(x0, y0, seed);
  const b = hash(x0 + 1, y0, seed);
  const c = hash(x0, y0 + 1, seed);
  const d = hash(x0 + 1, y0 + 1, seed);

  return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty;
}

function elevation(worldX: number, worldY: number): number {
  const broad = valueNoise(worldX * 0.035, worldY * 0.035, WORLD_SEED);
  const medium = valueNoise(worldX * 0.09, worldY * 0.09, WORLD_SEED + 17);
  const detail = valueNoise(worldX * 0.2, worldY * 0.2, WORLD_SEED + 31);
  return broad * 0.58 + medium * 0.3 + detail * 0.12;
}

function tileAt(worldX: number, worldY: number): TileKind {
  const e = elevation(worldX, worldY);

  if (e < 0.38) return TileKind.Ocean;
  if (e < 0.45) return TileKind.Shallow;
  if (e < 0.5) return TileKind.Sand;
  if (e > 0.78) return TileKind.Rock;
  return TileKind.Grass;
}

function nodeId(prefix: string, x: number, y: number): string {
  return `${prefix}:${x}:${y}`;
}

export function generateChunk(chunkX: number, chunkY: number): WorldChunk {
  const tiles = new Array<number>(CHUNK_SIZE * CHUNK_SIZE);
  const resources: ResourceNode[] = [];
  const creatures: CreatureSpawn[] = [];

  for (let localY = 0; localY < CHUNK_SIZE; localY += 1) {
    for (let localX = 0; localX < CHUNK_SIZE; localX += 1) {
      const worldX = chunkX * CHUNK_SIZE + localX;
      const worldY = chunkY * CHUNK_SIZE + localY;
      const kind = tileAt(worldX, worldY);
      tiles[localY * CHUNK_SIZE + localX] = kind;

      const roll = hash(worldX * 3 + 11, worldY * 5 + 7, WORLD_SEED + 101);

      if (kind === TileKind.Grass && roll > 0.985) {
        resources.push({
          id: nodeId("wood", worldX, worldY),
          type: "wood",
          x: worldX,
          y: worldY,
        });
      } else if (kind === TileKind.Rock && roll > 0.96) {
        resources.push({
          id: nodeId("stone", worldX, worldY),
          type: "stone",
          x: worldX,
          y: worldY,
        });
      } else if (kind === TileKind.Sand && roll > 0.992) {
        resources.push({
          id: nodeId("herb", worldX, worldY),
          type: "herb",
          x: worldX,
          y: worldY,
        });
      }

      const creatureRoll = hash(worldX * 7 + 19, worldY * 11 + 3, WORLD_SEED + 211);
      if (kind === TileKind.Grass && creatureRoll > 0.997) {
        const species = creatureRoll > 0.9994 ? "raptor" : creatureRoll > 0.9982 ? "boar" : "slime";
        creatures.push({
          id: nodeId("creature", worldX, worldY),
          species,
          x: worldX,
          y: worldY,
          level: 1 + Math.floor(hash(worldX, worldY, WORLD_SEED + 307) * 5),
        });
      }
    }
  }

  return {
    x: chunkX,
    y: chunkY,
    size: CHUNK_SIZE,
    tiles,
    resources,
    creatures,
  };
}

export class WorldChunkCache {
  private readonly chunks = new Map<string, WorldChunk>();

  constructor(private readonly maxChunks = 256) {}

  get(chunkX: number, chunkY: number): WorldChunk {
    const key = `${chunkX},${chunkY}`;
    const cached = this.chunks.get(key);

    if (cached) {
      this.chunks.delete(key);
      this.chunks.set(key, cached);
      return cached;
    }

    const generated = generateChunk(chunkX, chunkY);
    this.chunks.set(key, generated);

    while (this.chunks.size > this.maxChunks) {
      const oldest = this.chunks.keys().next().value;
      if (oldest === undefined) break;
      this.chunks.delete(oldest);
    }

    return generated;
  }

  get size(): number {
    return this.chunks.size;
  }
}
