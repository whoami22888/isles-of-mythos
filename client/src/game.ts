import Phaser from "phaser";
import { getAccessToken } from "./auth.js";
import { CHUNK_SIZE, TILE_SIZE, ChunkRenderer, type WorldChunk } from "./world.js";
import { isPlayerState, type PlayerState } from "./player.js";

const configuredBaseUrl = import.meta.env.VITE_API_BASE_URL;
const API_BASE_URL = (configuredBaseUrl ?? "http://localhost:3000").replace(/\/$/, "");
const WS_URL = API_BASE_URL.replace(/^http/, "ws") + "/ws";
const VISIBLE_CHUNK_RADIUS = 1;
const MOVE_SEND_INTERVAL_MS = 50;
const ATTACK_INPUT_COOLDOWN_MS = 150;

interface CombatResultMessage {
  type: "combat_result";
  targetId: string;
  damage: number;
  critical: boolean;
  killed: boolean;
  targetHealth: number;
  status?: string;
}

type ServerMessage =
  | { type: "server_ready"; timestamp: number }
  | { type: "pong"; timestamp: number }
  | { type: "auth_ok"; userId: string }
  | { type: "player_state"; state: PlayerState }
  | { type: "world_chunk"; requestId: string; chunk: WorldChunk }
  | CombatResultMessage
  | { type: "error"; code: string };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isWorldChunk(value: unknown): value is WorldChunk {
  if (!isRecord(value)) return false;
  return typeof value.x === "number" &&
    typeof value.y === "number" &&
    typeof value.size === "number" &&
    Array.isArray(value.tiles) &&
    value.tiles.every((tile) => typeof tile === "number");
}

function parseServerMessage(value: unknown): ServerMessage | null {
  if (!isRecord(value) || typeof value.type !== "string") return null;
  switch (value.type) {
    case "server_ready":
      return typeof value.timestamp === "number" ? { type: "server_ready", timestamp: value.timestamp } : null;
    case "pong":
      return typeof value.timestamp === "number" ? { type: "pong", timestamp: value.timestamp } : null;
    case "auth_ok":
      return typeof value.userId === "string" ? { type: "auth_ok", userId: value.userId } : null;
    case "player_state":
      return isPlayerState(value.state) ? { type: "player_state", state: value.state } : null;
    case "world_chunk":
      return typeof value.requestId === "string" && isWorldChunk(value.chunk)
        ? { type: "world_chunk", requestId: value.requestId, chunk: value.chunk }
        : null;
    case "combat_result":
      return typeof value.targetId === "string" &&
        typeof value.damage === "number" &&
        typeof value.critical === "boolean" &&
        typeof value.killed === "boolean" &&
        typeof value.targetHealth === "number" &&
        (value.status === undefined || typeof value.status === "string")
        ? {
            type: "combat_result",
            targetId: value.targetId,
            damage: value.damage,
            critical: value.critical,
            killed: value.killed,
            targetHealth: value.targetHealth,
            ...(value.status === undefined ? {} : { status: value.status }),
          }
        : null;
    case "error":
      return typeof value.code === "string" ? { type: "error", code: value.code } : null;
    default:
      return null;
  }
}

class WorldScene extends Phaser.Scene {
  private readonly chunks = new ChunkRenderer(this);
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
  private combatText?: Phaser.GameObjects.Text;
  private attackAccumulator = 0;
  private attackRequestSequence = 0;
  private reconnectTimer?: number;
  private reconnectAttempt = 0;
  private dodgeAccumulator = 0;

  constructor() { super("world"); }

  create(): void {
    this.cameras.main.setBackgroundColor("#07131f");
    this.cameras.main.centerOn(TILE_SIZE / 2, TILE_SIZE / 2);
    this.statusText = this.add.text(16, 16, "CONNECTING...", { fontFamily: "sans-serif", fontSize: "16px", color: "#ffffff", backgroundColor: "#07131fcc", padding: { left: 8, right: 8, top: 6, bottom: 6 } }).setScrollFactor(0).setDepth(1000);
    this.combatText = this.add.text(16, 100, "SPACE: ATTACK NEAREST CREATURE", { fontFamily: "sans-serif", fontSize: "14px", color: "#ffffff", backgroundColor: "#07131fcc", padding: { left: 8, right: 8, top: 6, bottom: 6 } }).setScrollFactor(0).setDepth(1000);
    this.survivalText = this.add.text(16, 58, "HP -- | STA -- | HUNGER -- | OXYGEN -- | HOTBAR 1", { fontFamily: "sans-serif", fontSize: "15px", color: "#ffffff", backgroundColor: "#07131fcc", padding: { left: 8, right: 8, top: 6, bottom: 6 } }).setScrollFactor(0).setDepth(1000);
    this.playerMarker = this.add.graphics().setDepth(50);
    this.cursors = this.input.keyboard?.createCursorKeys();
    this.keys = this.input.keyboard?.addKeys("W,A,S,D") as Record<string, Phaser.Input.Keyboard.Key> | undefined;
    this.input.keyboard?.on("keydown-SPACE", () => this.attackNearest());
    this.input.keyboard?.on("keydown-SHIFT", () => this.dodge());
    this.input.keyboard?.on("keydown-B", () => this.setBlocking(true));
    this.input.keyboard?.on("keyup-B", () => this.setBlocking(false));
    this.createTouchCombatControls();
    this.input.on("wheel", (_p: Phaser.Input.Pointer, _g: unknown[], _dx: number, dy: number) => this.cameras.main.setZoom(Phaser.Math.Clamp(this.cameras.main.zoom - dy * 0.001, 0.5, 2.5)));
    const hotbarKeys = ["ONE","TWO","THREE","FOUR","FIVE","SIX","SEVEN","EIGHT"];
    for (const key of hotbarKeys) {
      this.input.keyboard?.on("keydown-" + key, () => this.selectHotbar(hotbarKeys.indexOf(key)));
    }
    void this.connect();
  }

  update(_time: number, delta: number): void {
    if (!this.connected || !this.socket || this.socket.readyState !== WebSocket.OPEN) return;
    this.moveAccumulator += delta;
    this.attackAccumulator = Math.max(0, this.attackAccumulator - delta);
    this.dodgeAccumulator = Math.max(0, this.dodgeAccumulator - delta);
    if (this.moveAccumulator < MOVE_SEND_INTERVAL_MS) return;
    const dt = Math.min(this.moveAccumulator / 1000, 0.25);
    this.moveAccumulator = 0;
    let dx = 0, dy = 0;
    if (this.cursors?.left.isDown || this.keys?.A.isDown) dx -= 1;
    if (this.cursors?.right.isDown || this.keys?.D.isDown) dx += 1;
    if (this.cursors?.up.isDown || this.keys?.W.isDown) dy -= 1;
    if (this.cursors?.down.isDown || this.keys?.S.isDown) dy += 1;
    try {
      this.socket.send(JSON.stringify({ type: "move", dx, dy, dt }));
    } catch {
      this.connected = false;
      this.statusText?.setText("WORLD CONNECTION FAILED");
    }
  }

  private connect(): void {
    const token = getAccessToken();
    if (!token) { this.statusText?.setText("AUTHENTICATION REQUIRED"); return; }
    const socket = new WebSocket(WS_URL);
    this.socket = socket;
    socket.addEventListener("open", () => {
      try {
        socket.send(JSON.stringify({ type: "auth", token }));
      } catch {
        socket.close();
      }
    });
    socket.addEventListener("message", (event) => {
      let message: ServerMessage | null;
      try {
        message = parseServerMessage(JSON.parse(String(event.data)) as unknown);
      } catch {
        message = null;
      }
      if (!message) {
        this.statusText?.setText("INVALID SERVER MESSAGE");
        return;
      }
      if (message.type === "auth_ok") {
        this.connected = true;
        this.reconnectAttempt = 0;
        if (this.reconnectTimer !== undefined) {
          window.clearTimeout(this.reconnectTimer);
          this.reconnectTimer = undefined;
        }
        this.statusText?.setText("WORLD ONLINE • AUTHORITATIVE SERVER");
        this.requestChunks();
        return;
      }
      if (message.type === "player_state") {
        this.player = message.state;
        this.renderPlayer();
        this.updateHud();
        this.requestChunks();
        return;
      }
      if (message.type === "world_chunk") {
        this.chunks.render(message.chunk);
        this.updateHud();
        return;
      }
      if (message.type === "combat_result") {
        this.combatText?.setText(message.killed ? "DEFEATED • " + message.targetId : "HIT " + message.damage + (message.critical ? " CRITICAL" : "") + (message.status ? " • " + message.status.toUpperCase() : ""));
        this.time.delayedCall(900, () => this.combatText?.setText("SPACE: ATTACK NEAREST CREATURE"));
        return;
      }
      if (message.type === "error") {
        this.statusText?.setText("NETWORK ERROR • " + message.code);
      }
    });
    socket.addEventListener("close", () => {
      this.connected = false;
      this.statusText?.setText("WORLD OFFLINE • RECONNECTING...");
      this.scheduleReconnect();
    });
    socket.addEventListener("error", () => {
      this.connected = false;
      this.statusText?.setText("WORLD CONNECTION FAILED");
    });
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer !== undefined) return;
    const delay = Math.min(10_000, 1_000 * 2 ** Math.min(this.reconnectAttempt, 3));
    this.reconnectAttempt += 1;
    this.reconnectTimer = window.setTimeout(() => {
      this.reconnectTimer = undefined;
      this.connect();
    }, delay);
  }

  private requestChunks(): void {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN || !this.player) return;
    const centerChunkX = Math.floor(this.player.x / CHUNK_SIZE), centerChunkY = Math.floor(this.player.y / CHUNK_SIZE);
    if (centerChunkX === this.loadedCenter.x && centerChunkY === this.loadedCenter.y) return;
    this.loadedCenter = { x: centerChunkX, y: centerChunkY };
    const chunks: Array<{ x: number; y: number }> = [];
    for (let y = centerChunkY - VISIBLE_CHUNK_RADIUS; y <= centerChunkY + VISIBLE_CHUNK_RADIUS; y += 1) for (let x = centerChunkX - VISIBLE_CHUNK_RADIUS; x <= centerChunkX + VISIBLE_CHUNK_RADIUS; x += 1) chunks.push({ x, y });
    try {
      this.socket.send(JSON.stringify({ type: "subscribe_chunks", requestId: centerChunkX + ":" + centerChunkY + ":" + Date.now(), chunks }));
      this.chunks.unloadOutside(VISIBLE_CHUNK_RADIUS + 1, centerChunkX, centerChunkY);
    } catch {
      this.connected = false;
      this.statusText?.setText("WORLD CONNECTION FAILED");
    }
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
    this.survivalText?.setText("HP " + Math.ceil(this.player.health) + " | STA " + Math.ceil(this.player.stamina) + "/" + Math.ceil(this.player.maxStamina) + " | HUNGER " + Math.ceil(this.player.hunger) + " | OXYGEN " + Math.ceil(this.player.oxygen) + " | HOTBAR " + (this.player.selectedHotbarSlot + 1));
    this.statusText?.setText("WORLD ONLINE • chunks " + this.chunks.loadedCount + " • position " + this.player.x.toFixed(1) + ", " + this.player.y.toFixed(1));
  }

  private selectHotbar(slot: number): void {
    if (this.socket?.readyState !== WebSocket.OPEN) return;
    try {
      this.socket.send(JSON.stringify({ type: "select_hotbar", slot }));
    } catch {
      this.connected = false;
      this.statusText?.setText("WORLD CONNECTION FAILED");
    }
  }

  private dodge(): void {
    if (this.dodgeAccumulator > 0 || !this.player || this.socket?.readyState !== WebSocket.OPEN) return;
    const direction = this.cursors && (this.cursors.left.isDown || this.cursors.right.isDown || this.cursors.up.isDown || this.cursors.down.isDown)
      ? { x: Number(this.cursors.right.isDown) - Number(this.cursors.left.isDown), y: Number(this.cursors.down.isDown) - Number(this.cursors.up.isDown) }
      : { x: 0, y: 1 };
    if (direction.x === 0 && direction.y === 0) return;
    try {
      this.socket.send(JSON.stringify({ type: "dodge", facingX: direction.x, facingY: direction.y }));
      this.dodgeAccumulator = 900;
    } catch {
      this.connected = false;
      this.statusText?.setText("WORLD CONNECTION FAILED");
    }
  }

  private setBlocking(active: boolean): void {
    if (this.socket?.readyState !== WebSocket.OPEN) return;
    try { this.socket.send(JSON.stringify({ type: "block", active })); } catch {
      this.connected = false;
      this.statusText?.setText("WORLD CONNECTION FAILED");
    }
  }

  private createTouchCombatControls(): void {
    const makeButton = (label: string, x: number, y: number, onDown: () => void, onUp?: () => void): Phaser.GameObjects.Text => {
      const button = this.add.text(x, y, label, { fontFamily: "sans-serif", fontSize: "16px", color: "#ffffff", backgroundColor: "#17314dcc", padding: { left: 14, right: 14, top: 12, bottom: 12 } })
        .setScrollFactor(0).setDepth(1200).setInteractive({ useHandCursor: true });
      button.on("pointerdown", onDown);
      if (onUp) button.on("pointerup", onUp);
      button.on("pointerout", () => onUp?.());
      return button;
    };
    makeButton("ATTACK", 16, 650, () => this.attackNearest());
    makeButton("DODGE", 120, 650, () => this.dodge());
    makeButton("BLOCK", 214, 650, () => this.setBlocking(true), () => this.setBlocking(false));
  }

  private nextAttackRequestId(): string { return Date.now().toString(36) + "-" + (++this.attackRequestSequence).toString(36); }

  private attackNearest(): void {
    if (this.attackAccumulator > 0 || !this.player || this.socket?.readyState !== WebSocket.OPEN) return;
    const target = this.chunks.nearestCreature(this.player.x, this.player.y, 10);
    if (!target) {
      this.combatText?.setText("NO CREATURE IN RANGE");
      this.time.delayedCall(700, () => this.combatText?.setText("SPACE: ATTACK NEAREST CREATURE"));
      return;
    }
    const dx = target.x - this.player.x;
    const dy = target.y - this.player.y;
    try {
      this.socket.send(JSON.stringify({ type: "attack", requestId: this.nextAttackRequestId(), targetId: target.id, facingX: Math.sign(dx), facingY: Math.sign(dy) }));
      this.attackAccumulator = ATTACK_INPUT_COOLDOWN_MS;
    } catch {
      this.connected = false;
      this.statusText?.setText("WORLD CONNECTION FAILED");
    }
  }
}

export const gameConfig: Phaser.Types.Core.GameConfig = { type: Phaser.AUTO, parent: "game", width: 1280, height: 720, backgroundColor: "#07131f", scale: { mode: Phaser.Scale.RESIZE, autoCenter: Phaser.Scale.CENTER_BOTH }, scene: [WorldScene], render: { antialias: true, powerPreference: "high-performance" }, fps: { target: 60, forceSetTimeOut: false } };

export function startGame(): void { new Phaser.Game(gameConfig); }
