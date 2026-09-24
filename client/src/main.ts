import Phaser from "phaser";
import { ensureAuthenticated, getAccessToken } from "./auth.js";
import { GameState } from "./game-state.js";
import { CHUNK_SIZE, TILE_SIZE, ChunkRenderer, type WorldChunk } from "./world.js";
import type { PlayerState } from "./player.js";

const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL ?? "http://localhost:3000").replace(/\/$/, "");
const WS_URL = API_BASE_URL.replace(/^http/, "ws") + "/ws";
const VISIBLE_CHUNK_RADIUS = 1;
const MOVE_SEND_INTERVAL_MS = 50;

class WorldScene extends Phaser.Scene {
  private readonly chunks = new ChunkRenderer(this);
  private state = GameState.Overworld;
  private loadedCenter = { x: Number.NaN, y: Number.NaN };
  private statusText?: Phaser.GameObjects.Text;
  private survivalText?: Phaser.GameObjects.Text;
  private playerMarker?: Phaser.GameObjects.Graphics;
  private socket?: WebSocket;
  private player?: PlayerState;
  private cursors?: Phaser.Types.Input.Keyboard.CursorKeys;
  private keys?: Record<string, Phaser.Input.Keyboard.Key>;
  private moveAccumulator = 0;
  private connected = false;

  constructor() { super("world"); }

  create(): void {
    this.cameras.main.setBackgroundColor("#07131f");
    this.cameras.main.centerOn(TILE_SIZE / 2, TILE_SIZE / 2);
    this.statusText = this.add.text(16, 16, "CONNECTING...", { fontFamily: "sans-serif", fontSize: "16px", color: "#ffffff", backgroundColor: "#07131fcc", padding: { left: 8, right: 8, top: 6, bottom: 6 } }).setScrollFactor(0).setDepth(1000);
    this.survivalText = this.add.text(16, 58, "HP -- | HUNGER -- | OXYGEN -- | HOTBAR 1", { fontFamily: "sans-serif", fontSize: "15px", color: "#ffffff", backgroundColor: "#07131fcc", padding: { left: 8, right: 8, top: 6, bottom: 6 } }).setScrollFactor(0).setDepth(1000);
    this.playerMarker = this.add.graphics().setDepth(50);
    this.cursors = this.input.keyboard?.createCursorKeys();
    this.keys = this.input.keyboard?.addKeys("W,A,S,D") as Record<string, Phaser.Input.Keyboard.Key> | undefined;
    this.input.on("wheel", (_p: Phaser.Input.Pointer, _g: unknown[], _dx: number, dy: number) => this.cameras.main.setZoom(Phaser.Math.Clamp(this.cameras.main.zoom - dy * 0.001, 0.5, 2.5)));
    for (const key of ["ONE","TWO","THREE","FOUR","FIVE","SIX","SEVEN","EIGHT"]) {
      this.input.keyboard?.on("keydown-" + key, () => this.selectHotbar(["ONE","TWO","THREE","FOUR","FIVE","SIX","SEVEN","EIGHT"].indexOf(key)));
    }
    void this.connect();
  }

  update(_time: number, delta: number): void {
    if (!this.connected || !this.socket || this.socket.readyState !== WebSocket.OPEN) return;
    this.moveAccumulator += delta;
    if (this.moveAccumulator < MOVE_SEND_INTERVAL_MS) return;
    const dt = Math.min(this.moveAccumulator / 1000, 0.25);
    this.moveAccumulator = 0;
    let dx = 0, dy = 0;
    if (this.cursors?.left.isDown || this.keys?.A.isDown) dx -= 1;
    if (this.cursors?.right.isDown || this.keys?.D.isDown) dx += 1;
    if (this.cursors?.up.isDown || this.keys?.W.isDown) dy -= 1;
    if (this.cursors?.down.isDown || this.keys?.S.isDown) dy += 1;
    this.socket.send(JSON.stringify({ type: "move", dx, dy, dt }));
  }

  private async connect(): Promise<void> {
    const token = getAccessToken();
    if (!token) { this.statusText?.setText("AUTHENTICATION REQUIRED"); return; }
    const socket = new WebSocket(WS_URL);
    this.socket = socket;
    socket.addEventListener("open", () => socket.send(JSON.stringify({ type: "auth", token })));
    socket.addEventListener("message", (event) => {
      let message: { type: string; state?: PlayerState; chunk?: WorldChunk };
      try { message = JSON.parse(String(event.data)) as typeof message; } catch { return; }
      if (message.type === "auth_ok") { this.connected = true; this.statusText?.setText("WORLD ONLINE • AUTHORITATIVE SERVER"); this.requestChunks(); return; }
      if (message.type === "player_state" && message.state) { this.player = message.state; this.renderPlayer(); this.updateHud(); this.requestChunks(); return; }
      if (message.type === "world_chunk" && message.chunk) { this.chunks.render(message.chunk); this.updateHud(); }
      if (message.type === "error") this.statusText?.setText("NETWORK ERROR");
    });
    socket.addEventListener("close", () => { this.connected = false; this.statusText?.setText("WORLD OFFLINE • RECONNECT REQUIRED"); });
    socket.addEventListener("error", () => { this.connected = false; this.statusText?.setText("WORLD CONNECTION FAILED"); });
  }

  private requestChunks(): void {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN || !this.player) return;
    const centerChunkX = Math.floor(this.player.x / CHUNK_SIZE), centerChunkY = Math.floor(this.player.y / CHUNK_SIZE);
    if (centerChunkX === this.loadedCenter.x && centerChunkY === this.loadedCenter.y) return;
    this.loadedCenter = { x: centerChunkX, y: centerChunkY };
    const chunks: Array<{ x: number; y: number }> = [];
    for (let y = centerChunkY - VISIBLE_CHUNK_RADIUS; y <= centerChunkY + VISIBLE_CHUNK_RADIUS; y += 1) for (let x = centerChunkX - VISIBLE_CHUNK_RADIUS; x <= centerChunkX + VISIBLE_CHUNK_RADIUS; x += 1) chunks.push({ x, y });
    this.socket.send(JSON.stringify({ type: "subscribe_chunks", requestId: centerChunkX + ":" + centerChunkY + ":" + Date.now(), chunks }));
    this.chunks.unloadOutside(VISIBLE_CHUNK_RADIUS + 1, centerChunkX, centerChunkY);
  }

  private renderPlayer(): void {
    if (!this.player || !this.playerMarker) return;
    const px = this.player.x * TILE_SIZE + TILE_SIZE / 2, py = this.player.y * TILE_SIZE + TILE_SIZE / 2;
    this.playerMarker.clear(); this.playerMarker.fillStyle(0xffd166, 1); this.playerMarker.fillCircle(px, py, TILE_SIZE * 0.32);
    this.playerMarker.lineStyle(2, 0xffffff, 1); this.playerMarker.strokeCircle(px, py, TILE_SIZE * 0.34);
    this.cameras.main.startFollow(this.playerMarker, true, 0.12, 0.12);
  }

  private updateHud(): void {
    if (!this.player) return;
    this.survivalText?.setText("HP " + Math.ceil(this.player.health) + " | HUNGER " + Math.ceil(this.player.hunger) + " | OXYGEN " + Math.ceil(this.player.oxygen) + " | HOTBAR " + (this.player.selectedHotbarSlot + 1));
    this.statusText?.setText("WORLD ONLINE • chunks " + this.chunks.loadedCount + " • position " + this.player.x.toFixed(1) + ", " + this.player.y.toFixed(1));
  }

  private selectHotbar(slot: number): void { if (this.socket?.readyState === WebSocket.OPEN) this.socket.send(JSON.stringify({ type: "select_hotbar", slot })); }
}

export const gameConfig: Phaser.Types.Core.GameConfig = { type: Phaser.AUTO, parent: "game", width: 1280, height: 720, backgroundColor: "#07131f", scale: { mode: Phaser.Scale.RESIZE, autoCenter: Phaser.Scale.CENTER_BOTH }, scene: [WorldScene], render: { antialias: true, powerPreference: "high-performance" }, fps: { target: 60, forceSetTimeOut: false } };

void ensureAuthenticated().then(() => { new Phaser.Game(gameConfig); }).catch((error) => { const game = document.getElementById("game"); if (game) game.textContent = error instanceof Error ? error.message : "Authentication failed"; });