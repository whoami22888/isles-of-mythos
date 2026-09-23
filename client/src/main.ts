import Phaser from "phaser";
import { GameState } from "./game-state.js";
import { CHUNK_SIZE, TILE_SIZE, ChunkRenderer, type WorldChunk } from "./world.js";

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:3000";
const VISIBLE_CHUNK_RADIUS = 1;

class WorldScene extends Phaser.Scene {
  private readonly chunks = new ChunkRenderer(this);
  private state = GameState.Overworld;
  private loadedCenter = { x: Number.NaN, y: Number.NaN };
  private statusText?: Phaser.GameObjects.Text;

  constructor() {
    super("world");
  }

  create(): void {
    this.cameras.main.setBackgroundColor("#07131f");
    this.cameras.main.centerOn(0, 0);
    this.cameras.main.setZoom(1);

    this.statusText = this.add.text(16, 16, "Loading world...", {
      fontFamily: "sans-serif",
      fontSize: "16px",
      color: "#ffffff",
      backgroundColor: "#07131fcc",
      padding: { left: 8, right: 8, top: 6, bottom: 6 },
    });
    this.statusText.setScrollFactor(0).setDepth(1000);

    this.input.on("wheel", (_pointer: Phaser.Input.Pointer, _gameObjects: unknown[], _dx: number, dy: number) => {
      const next = Phaser.Math.Clamp(this.cameras.main.zoom - dy * 0.001, 0.5, 2.5);
      this.cameras.main.setZoom(next);
    });

    void this.loadVisibleChunks(true);
  }

  update(): void {
    const camera = this.cameras.main;
    const centerChunkX = Math.floor(camera.worldView.centerX / (CHUNK_SIZE * TILE_SIZE));
    const centerChunkY = Math.floor(camera.worldView.centerY / (CHUNK_SIZE * TILE_SIZE));

    if (centerChunkX !== this.loadedCenter.x || centerChunkY !== this.loadedCenter.y) {
      void this.loadVisibleChunks(false);
    }
  }

  private async loadVisibleChunks(force: boolean): Promise<void> {
    const camera = this.cameras.main;
    const centerChunkX = Math.floor(camera.worldView.centerX / (CHUNK_SIZE * TILE_SIZE));
    const centerChunkY = Math.floor(camera.worldView.centerY / (CHUNK_SIZE * TILE_SIZE));

    if (!force && centerChunkX === this.loadedCenter.x && centerChunkY === this.loadedCenter.y) return;

    this.loadedCenter = { x: centerChunkX, y: centerChunkY };

    const requests: Promise<WorldChunk>[] = [];
    for (let y = centerChunkY - VISIBLE_CHUNK_RADIUS; y <= centerChunkY + VISIBLE_CHUNK_RADIUS; y += 1) {
      for (let x = centerChunkX - VISIBLE_CHUNK_RADIUS; x <= centerChunkX + VISIBLE_CHUNK_RADIUS; x += 1) {
        requests.push(
          fetch(`${API_BASE_URL}/world/chunks/${x}/${y}`).then(async (response) => {
            if (!response.ok) throw new Error(`World chunk request failed: HTTP ${response.status}`);
            return response.json() as Promise<WorldChunk>;
          }),
        );
      }
    }

    try {
      const chunks = await Promise.all(requests);
      for (const chunk of chunks) this.chunks.render(chunk);
      this.chunks.unloadOutside(VISIBLE_CHUNK_RADIUS + 1, centerChunkX, centerChunkY);
      this.statusText?.setText(`WORLD ONLINE • chunks ${this.chunks.loadedCount} • ${this.state}`);
    } catch (error) {
      this.statusText?.setText(
        `WORLD OFFLINE • ${error instanceof Error ? error.message : "unknown error"}`,
      );
    }
  }
}

export const gameConfig: Phaser.Types.Core.GameConfig = {
  type: Phaser.AUTO,
  parent: "game",
  width: 1280,
  height: 720,
  backgroundColor: "#07131f",
  scale: {
    mode: Phaser.Scale.RESIZE,
    autoCenter: Phaser.Scale.CENTER_BOTH,
  },
  scene: [WorldScene],
  render: {
    antialias: true,
    powerPreference: "high-performance",
  },
  fps: {
    target: 60,
    forceSetTimeOut: false,
  },
};

new Phaser.Game(gameConfig);
