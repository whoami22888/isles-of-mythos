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
  creatures?: CreatureSpawn[];
}

const TILE_COLORS: Record<number, number> = {
  [TileKind.Ocean]: 0x123b62,
  [TileKind.Shallow]: 0x1c6680,
  [TileKind.Sand]: 0xd5bc76,
  [TileKind.Grass]: 0x3d7b49,
  [TileKind.Rock]: 0x5c6470,
  [TileKind.Reef]: 0x2b8a83,
};

export class ChunkRenderer {
  private readonly chunks = new Map<string, Phaser.GameObjects.Graphics>();
  private readonly creatures = new Map<string, Phaser.GameObjects.Graphics>();

  constructor(private readonly scene: Phaser.Scene) {}

  render(chunk: WorldChunk): void {
    const key = `${chunk.x},${chunk.y}`;
    if (this.chunks.has(key)) return;

    const graphics = this.scene.add.graphics();
    const originX = chunk.x * chunk.size * TILE_SIZE;
    const originY = chunk.y * chunk.size * TILE_SIZE;

    for (let y = 0; y < chunk.size; y += 1) {
      let currentKind = -1;
      for (let x = 0; x < chunk.size; x += 1) {
        const kind = chunk.tiles[y * chunk.size + x] ?? TileKind.Ocean;
        if (kind !== currentKind) {
          graphics.fillStyle(TILE_COLORS[kind] ?? TILE_COLORS[TileKind.Ocean], 1);
          currentKind = kind;
        }
        graphics.fillRect(
          originX + x * TILE_SIZE,
          originY + y * TILE_SIZE,
          TILE_SIZE + 1,
          TILE_SIZE + 1,
        );
      }
    }

    graphics.setDepth(-100);
    this.chunks.set(key, graphics);

    for (const creature of chunk.creatures ?? []) {
      if (this.creatures.has(creature.id)) continue;
      const marker = this.scene.add.graphics();
      const color = creature.species === "raptor" ? 0xd95f59 : creature.species === "boar" ? 0x8b6f47 : 0x6bcf63;
      marker.fillStyle(color, 1);
      marker.fillCircle(creature.x * TILE_SIZE + TILE_SIZE / 2, creature.y * TILE_SIZE + TILE_SIZE / 2, TILE_SIZE * 0.25);
      marker.lineStyle(1, 0xffffff, 0.8);
      marker.strokeCircle(creature.x * TILE_SIZE + TILE_SIZE / 2, creature.y * TILE_SIZE + TILE_SIZE / 2, TILE_SIZE * 0.28);
      marker.setDepth(10);
      this.creatures.set(creature.id, marker);
    }
  }

  unloadOutside(radius: number, centerChunkX: number, centerChunkY: number): void {
    for (const [key, graphics] of this.chunks) {
      const [x, y] = key.split(",").map(Number);
      if (Math.abs(x - centerChunkX) > radius || Math.abs(y - centerChunkY) > radius) {
        graphics.destroy();
        this.chunks.delete(key);
        for (const [creatureId, marker] of this.creatures) {
          if (creatureId.startsWith("creature:")) {
            const parts = creatureId.split(":").map(Number);
            const cx = Math.floor(parts[1] / CHUNK_SIZE);
            const cy = Math.floor(parts[2] / CHUNK_SIZE);
            if (cx === x && cy === y) {
              marker.destroy();
              this.creatures.delete(creatureId);
            }
          }
        }
      }
    }
  }

  get loadedCount(): number {
    return this.chunks.size;
  }

  nearestCreature(x: number, y: number, maxDistance = 10): { id: string; x: number; y: number } | null {
    let nearest: { id: string; x: number; y: number } | null = null;
    let nearestDistance = maxDistance;
    for (const [id, marker] of this.creatures) {
      const worldX = marker.x / TILE_SIZE;
      const worldY = marker.y / TILE_SIZE;
      const d = Math.hypot(worldX - x, worldY - y);
      if (d < nearestDistance) {
        nearest = { id, x: worldX, y: worldY };
        nearestDistance = d;
      }
    }
    return nearest;
  }
}
