import { describe, expect, it } from "vitest";
import { CHUNK_SIZE, TILE_SIZE, TileKind, ChunkRenderer } from "./world.js";

describe("client world constants", () => {
  it("uses the same chunk geometry as the server contract", () => {
    expect(CHUNK_SIZE).toBe(32);
    expect(TILE_SIZE).toBe(32);
    expect(TileKind.Ocean).toBe(0);
    expect(TileKind.Grass).toBe(3);
    expect(TileKind.Reef).toBe(5);
  });
});

function createFakeScene() {
  let created = 0;
  let destroyed = 0;
  let filledRects = 0;
  const makeGraphics = () => {
    created += 1;
    const graphics = {
      fillStyle: () => graphics,
      fillRect: () => { filledRects += 1; return graphics; },
      fillCircle: () => graphics,
      lineStyle: () => graphics,
      strokeCircle: () => graphics,
      setDepth: () => graphics,
      clear: () => graphics,
      destroy: () => { destroyed += 1; },
    };
    return graphics;
  };
  return {
    scene: { add: { graphics: makeGraphics } },
    created: () => created,
    destroyed: () => destroyed,
    filledRects: () => filledRects,
  };
}

describe("chunk entity batching", () => {
  it("uses two graphics objects per chunk regardless of entity count", () => {
    const fake = createFakeScene();
    const renderer = new ChunkRenderer(fake.scene as never);
    renderer.render({
      x: 0,
      y: 0,
      size: 1,
      tiles: [TileKind.Grass],
      resources: [
        { id: "wood:0:0", type: "wood", x: 0, y: 0 },
        { id: "stone:1:0", type: "stone", x: 1, y: 0 },
      ],
      creatures: [
        { id: "creature:0:0", species: "slime", x: 0, y: 1, level: 1 },
        { id: "creature:1:0", species: "raptor", x: 1, y: 1, level: 2 },
      ],
    });

    expect(renderer.loadedCount).toBe(1);
    expect(fake.created()).toBe(2);
    expect(renderer.nearestResource(0, 0)?.id).toBe("wood:0:0");
    expect(renderer.nearestResource(1, 0)?.id).toBe("stone:1:0");
    expect(renderer.nearestCreature(0, 1)?.id).toBe("creature:0:0");
    expect(renderer.nearestCreature(1, 1)?.id).toBe("creature:1:0");
  });

  it("renders level-seven resource-mill spawn points on the shared entity layer", () => {
    const fake = createFakeScene();
    const renderer = new ChunkRenderer(fake.scene as never);
    renderer.render({
      x: 0,
      y: 0,
      size: 1,
      tiles: [TileKind.Grass],
      resourceMillSpawns: [{ id: "resource-mill-lv7:0:0", x: 0, y: 0, level: 7 }],
    });

    expect(renderer.loadedCount).toBe(1);
    expect(fake.created()).toBe(2);
    expect(fake.filledRects()).toBe(2);
    renderer.unloadOutside(0, 1, 1);
    expect(renderer.loadedCount).toBe(0);
  });

  it("redraws a shared marker layer when entities are removed without allocating more objects", () => {
    const fake = createFakeScene();
    const renderer = new ChunkRenderer(fake.scene as never);
    renderer.render({
      x: 0,
      y: 0,
      size: 1,
      tiles: [TileKind.Grass],
      resources: [{ id: "wood:0:0", type: "wood", x: 0, y: 0 }],
      creatures: [{ id: "creature:0:0", species: "slime", x: 1, y: 1, level: 1 }],
    });

    renderer.removeResource("wood:0:0");
    renderer.removeCreature("creature:0:0");
    expect(renderer.nearestResource(0, 0)).toBeNull();
    expect(renderer.nearestCreature(1, 1)).toBeNull();
    expect(fake.created()).toBe(2);
  });

  it("destroys both shared layers and indexed entities when unloading a chunk", () => {
    const fake = createFakeScene();
    const renderer = new ChunkRenderer(fake.scene as never);
    renderer.render({
      x: 0,
      y: 0,
      size: 1,
      tiles: [TileKind.Grass],
      resources: [{ id: "wood:0:0", type: "wood", x: 0, y: 0 }],
      creatures: [{ id: "creature:0:0", species: "slime", x: 1, y: 1, level: 1 }],
    });

    renderer.unloadOutside(0, 1, 1);
    expect(renderer.loadedCount).toBe(0);
    expect(fake.destroyed()).toBe(2);
    expect(renderer.nearestResource(0, 0)).toBeNull();
    expect(renderer.nearestCreature(1, 1)).toBeNull();
  });
});
