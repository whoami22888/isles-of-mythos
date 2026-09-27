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

interface ProjectileSpawnMessage {
  type: "projectile_spawn";
  projectileId: string;
  ownerUserId: string;
  targetId: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  expiresAt: number;
}

interface CreatureStateMessage { type: "creature_state"; requestId?: string; creature: { id: string; species: string; tameProgress: number; partySlot: number | null; aiMode: "follow" | "assist" | "stay" } }
interface CreaturePartyMessage { type: "creature_party"; creatures: CreatureStateMessage["creature"][] }

interface CreatureMessage { type: "creature_state"; requestId?: string; creature: CreatureState; }\ninterface CreaturePartyMessage { type: "creature_party"; creatures: CreatureState[]; }\ninterface CreatureState { id:string; species:string; nickname:string|null; level:number; health:number; maxHealth:number; tameProgress:number; partySlot:number|null; aiMode:"follow"|"assist"|"stay"; x:number; y:number; }\n\ninterface CombatResultMessage {
  type: "combat_result";
  requestId: string;
  targetId: string;
  damage: number;
  critical: boolean;
  killed: boolean;
  targetHealth: number;
  status?: string;
  missed?: boolean;
}

type ServerMessage =
  | { type: "server_ready"; timestamp: number }
  | { type: "pong"; timestamp: number }
  | { type: "auth_ok"; userId: string }
  | { type: "player_state"; state: PlayerState }
  | { type: "world_chunk"; requestId: string; chunk: WorldChunk }
  | ProjectileSpawnMessage
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
    case "projectile_spawn":
      return typeof value.projectileId === "string" && typeof value.ownerUserId === "string" && typeof value.targetId === "string" &&
        typeof value.x === "number" && Number.isFinite(value.x) && typeof value.y === "number" && Number.isFinite(value.y) &&
        typeof value.vx === "number" && Number.isFinite(value.vx) && typeof value.vy === "number" && Number.isFinite(value.vy) &&
        typeof value.expiresAt === "number" && Number.isFinite(value.expiresAt)
        ? { type: "projectile_spawn", projectileId: value.projectileId, ownerUserId: value.ownerUserId, targetId: value.targetId, x: value.x, y: value.y, vx: value.vx, vy: value.vy, expiresAt: value.expiresAt }
        : null;
    case "creature_state":\n      if (!isRecord(value.creature) || typeof value.creature.id !== "string" || typeof value.creature.species !== "string" || typeof value.creature.tameProgress !== "number" || (value.creature.partySlot !== null && typeof value.creature.partySlot !== "number") || !["follow","assist","stay"].includes(String(value.creature.aiMode))) return null;\n      return { type: "creature_state", requestId: typeof value.requestId === "string" ? value.requestId : undefined, creature: { id:value.creature.id, species:value.creature.species, tameProgress:value.creature.tameProgress, partySlot:value.creature.partySlot as number|null, aiMode:value.creature.aiMode as "follow"|"assist"|"stay" } };\n    case "creature_party":\n      if (!Array.isArray(value.creatures)) return null;\n      return { type: "creature_party", creatures: value.creatures.filter(isRecord).filter(c => typeof c.id === "string" && typeof c.species === "string" && typeof c.tameProgress === "number" && (c.partySlot === null || typeof c.partySlot === "number") && ["follow","assist","stay"].includes(String(c.aiMode))).map(c => ({ id:c.id as string, species:c.species as string, tameProgress:c.tameProgress as number, partySlot:c.partySlot as number|null, aiMode:c.aiMode as "follow"|"assist"|"stay" })) };\n    case "combat_result":
      return typeof value.requestId === "string" && value.requestId.length > 0 && value.requestId.length <= 64 &&
        typeof value.targetId === "string" &&
        typeof value.damage === "number" &&
        typeof value.critical === "boolean" &&
        typeof value.killed === "boolean" &&
        typeof value.targetHealth === "number" &&
        (value.status === undefined || typeof value.status === "string") &&
        (value.missed === undefined || typeof value.missed === "boolean")
        ? {
            type: "combat_result",
            requestId: value.requestId,
            targetId: value.targetId,
            damage: value.damage,
            critical: value.critical,
            killed: value.killed,
            targetHealth: value.targetHealth,
            ...(value.missed === undefined ? {} : { missed: value.missed }),
            ...(value.status === undefined ? {} : { status: value.status }),
          }
        : null;
    case "creature_state":\n      return isRecord(value.creature) && typeof value.creature.id === "string" && typeof value.creature.species === "string" && typeof value.creature.tameProgress === "number" && typeof value.creature.x === "number" && typeof value.creature.y === "number"\n        ? { type: "creature_state", ...(typeof value.requestId === "string" ? { requestId: value.requestId } : {}), creature: value.creature as CreatureState } : null;\n    case "creature_party":\n      return Array.isArray(value.creatures) && value.creatures.every((x) => isRecord(x) && typeof x.id === "string")\n        ? { type: "creature_party", creatures: value.creatures as CreatureState[] } : null;\n    case "error":
      return typeof value.code === "string" ? { type: "error", code: value.code } : null;
    default:
      return null;
  }
}

class WorldScene extends Phaser.Scene {
  private readonly chunks = new ChunkRenderer(this);
  private readonly projectiles = new Map<string, Phaser.GameObjects.Graphics>();
  private readonly projectileByRequest = new Map<string, string>();
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
  private dodgeAccumulator = 0;\n  private readonly ownedCreatures = new Map<string, CreatureState>();\n  private creatureParty: CreatureStateMessage["creature"][] = [];\n  private selectedCreatureId?: string;

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
    this.input.keyboard?.on("keydown-B", () => this.setBlocking(true));\n    this.input.keyboard?.on("keydown-C", () => this.captureNearest());\n    this.input.keyboard?.on("keydown-T", () => this.tameSelected());
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
      if (message.type === "creature_party") {\n        this.ownedCreatures.clear();\n        for (const creature of message.creatures) this.ownedCreatures.set(creature.id, creature);\n        return;\n      }\n      if (message.type === "creature_state") {\n        this.ownedCreatures.set(message.creature.id, message.creature);\n        this.combatText?.setText(message.creature.tameProgress >= 100 ? `${message.creature.species.toUpperCase()} TAMED` : `${message.creature.species.toUpperCase()} TAME ${message.creature.tameProgress}%`);\n        return;\n      }\n      if (message.type === "projectile_spawn") {
        this.renderProjectile(message);
        return;
      }
      if (message.type === "creature_party") { this.creatureParty = message.creatures; if (message.creatures.length > 0 && !this.selectedCreatureId) this.selectedCreatureId = message.creatures[0].id; this.combatText?.setText("CREATURE PARTY • " + message.creatures.length); return; }\n      if (message.type === "creature_state") { this.selectedCreatureId = message.creature.id; const i=this.creatureParty.findIndex(c=>c.id===message.creature.id); if(i>=0)this.creatureParty[i]=message.creature; else this.creatureParty.push(message.creature); this.combatText?.setText("CREATURE • "+message.creature.species+" • TAME "+message.creature.tameProgress+"%"); return; }\n      if (message.type === "combat_result") {
        const projectileId = this.projectileByRequest.get(message.requestId);
        if (projectileId) {
          this.projectiles.get(projectileId)?.destroy();
          this.projectiles.delete(projectileId);
          this.projectileByRequest.delete(message.requestId);
        }
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

  private creatureRequestId(prefix: string): string { return prefix + "-" + Date.now().toString(36) + "-" + (++this.attackRequestSequence).toString(36); }\n\n  private captureNearest(): void {\n    if (!this.socket || this.socket.readyState !== WebSocket.OPEN || !this.player) return;\n    const target=this.chunks.nearestCreature(this.player.x,this.player.y,2.5);\n    if(!target){this.combatText?.setText("NO CREATURE IN CAPTURE RANGE");return;}\n    this.socket.send(JSON.stringify({type:"capture",requestId:this.creatureRequestId("capture"),targetId:target.id}));\n  }\n\n  private tameSelected(): void {\n    if(!this.selectedCreatureId || this.socket?.readyState!==WebSocket.OPEN){this.combatText?.setText("NO CREATURE SELECTED");return;}\n    this.socket.send(JSON.stringify({type:"tame",requestId:this.creatureRequestId("tame"),creatureId:this.selectedCreatureId}));\n  }\n\n  private setCreatureParty(): void {\n    if(!this.selectedCreatureId || this.socket?.readyState!==WebSocket.OPEN){this.combatText?.setText("NO CREATURE SELECTED");return;}\n    this.socket.send(JSON.stringify({type:"set_creature_party",requestId:this.creatureRequestId("party"),creatureId:this.selectedCreatureId,slot:0}));\n  }\n\n  private setCreatureAi(mode: "follow"|"assist"|"stay"): void {\n    if(!this.selectedCreatureId || this.socket?.readyState!==WebSocket.OPEN){this.combatText?.setText("NO CREATURE SELECTED");return;}\n    this.socket.send(JSON.stringify({type:"set_creature_ai",requestId:this.creatureRequestId("ai"),creatureId:this.selectedCreatureId,mode}));\n  }\n\n  private setBlocking(active: boolean): void {
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
    makeButton("BLOCK", 214, 650, () => this.setBlocking(true), () => this.setBlocking(false));\n    makeButton("CAPTURE", 318, 650, () => this.captureNearest());\n    makeButton("TAME", 426, 650, () => this.tameSelected());\n    makeButton("CAPTURE", 308, 650, () => this.captureNearest());\n    makeButton("TAME", 420, 650, () => this.tameSelected());\n    makeButton("PARTY", 502, 650, () => this.setCreatureParty());\n    makeButton("STAY", 590, 650, () => this.setCreatureAi("stay"));
  }

  private renderProjectile(message: ProjectileSpawnMessage): void {
    const marker = this.add.graphics().setDepth(30);
    marker.fillStyle(0xffd166, 1);
    marker.fillCircle(0, 0, TILE_SIZE * 0.12);
    marker.setPosition(message.x * TILE_SIZE + TILE_SIZE / 2, message.y * TILE_SIZE + TILE_SIZE / 2);
    this.projectiles.set(message.projectileId, marker);
    const separator = message.projectileId.lastIndexOf(":");
    const requestId = separator >= 0 ? message.projectileId.slice(separator + 1) : message.projectileId;
    this.projectileByRequest.set(requestId, message.projectileId);
    const lifetime = Math.max(1, message.expiresAt - Date.now());
    this.tweens.add({
      targets: marker,
      x: marker.x + message.vx * TILE_SIZE * (lifetime / 1000),
      y: marker.y + message.vy * TILE_SIZE * (lifetime / 1000),
      duration: lifetime,
      ease: "Linear",
      onComplete: () => {
        marker.destroy();
        this.projectiles.delete(message.projectileId);
        this.projectileByRequest.delete(requestId);
      },
    });
  }

  private captureNearest(): void {\n    if (!this.player || this.socket?.readyState !== WebSocket.OPEN) return;\n    const target = this.chunks.nearestCreature(this.player.x, this.player.y, 2.5);\n    if (!target) { this.combatText?.setText("NO CREATURE IN CAPTURE RANGE"); return; }\n    this.socket.send(JSON.stringify({ type: "capture", requestId: this.nextAttackRequestId(), targetId: target.id }));\n  }\n\n  private tameSelected(): void {\n    if (this.socket?.readyState !== WebSocket.OPEN) return;\n    const creature = [...this.ownedCreatures.values()].find((x) => x.partySlot !== null) ?? [...this.ownedCreatures.values()][0];\n    if (!creature) { this.combatText?.setText("NO OWNED CREATURE"); return; }\n    this.socket.send(JSON.stringify({ type: "tame", requestId: this.nextAttackRequestId(), creatureId: creature.id }));\n  }\n\n  private nextAttackRequestId(): string { return Date.now().toString(36) + "-" + (++this.attackRequestSequence).toString(36); }

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
