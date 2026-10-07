import Phaser from "phaser";
import { getAccessToken } from "./auth.js";
import { CHUNK_SIZE, TILE_SIZE, ChunkRenderer } from "./world.js";
import type { PlayerState } from "./player.js";
import {
  parseServerMessage,
  type ArmySummary,
  type CreatureState,
  type InvasionRole,
  type InvasionSummary,
  type InvasionWave,
  type ProjectileSpawnMessage,
  type ServerMessage,
} from "./network.js";

const configuredBaseUrl = import.meta.env.VITE_API_BASE_URL;
const API_BASE_URL = (configuredBaseUrl ?? window.location.origin).replace(/\/$/, "");
const WS_URL = API_BASE_URL.replace(/^http/, (protocol) => protocol === "https" ? "wss" : "ws") + "/ws";
const VISIBLE_CHUNK_RADIUS = 1;
const MOVE_SEND_INTERVAL_MS = 50;
const ATTACK_INPUT_COOLDOWN_MS = 150;

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
  private dodgeAccumulator = 0;
  private readonly ownedCreatures = new Map<string, CreatureState>();
  private readonly pendingCaptureTargets = new Map<string, string>();
  private invasion?: InvasionSummary;
  private invasionWaves: InvasionWave[] = [];
  private availableArmies: ArmySummary[] = [];
  private invasionRoleIndex = 1;
  private invasionPanel?: Phaser.GameObjects.Rectangle;
  private invasionTitle?: Phaser.GameObjects.Text;
  private invasionInfo?: Phaser.GameObjects.Text;
  private invasionWaveInfo?: Phaser.GameObjects.Text;
  private invasionRoleText?: Phaser.GameObjects.Text;
  private invasionJoinButton?: Phaser.GameObjects.Text;
  private invasionRoleButton?: Phaser.GameObjects.Text;
  private invasionAttackButton?: Phaser.GameObjects.Text;
  private invasionReinforceButton?: Phaser.GameObjects.Text;
  private invasionRetreatButton?: Phaser.GameObjects.Text;

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
    this.input.keyboard?.on("keydown-C", () => this.captureNearest());
    this.input.keyboard?.on("keydown-T", () => this.tameSelected());
    this.input.keyboard?.on("keydown-P", () => this.togglePartySelected());
    this.input.keyboard?.on("keydown-I", () => this.cycleSelectedAi());
    this.input.keyboard?.on("keyup-B", () => this.setBlocking(false));
    this.createTouchCombatControls();
    this.createInvasionOverlay();
    this.time.addEvent({ delay: 3000, loop: true, callback: () => this.refreshInvasions() });
    this.scale.on("resize", () => this.layoutInvasionOverlay());
    this.layoutInvasionOverlay();
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
        this.requestArmies();
        this.refreshInvasions();
        return;
      }
      if (message.type === "army_list") {
        this.availableArmies = message.armies;
        this.renderInvasionOverlay();
        return;
      }
      if (message.type === "invasion_list") {
        const active = message.invasions.find((x) => x.phase !== "COMPLETE") ?? message.invasions[0];
        this.invasion = active;
        if (!active) this.invasionWaves = [];
        if (active) this.requestInvasionWaves(active.id);
        this.renderInvasionOverlay();
        return;
      }
      if (message.type === "invasion_waves") {
        if (!this.invasion || this.invasion.id === message.invasionId) this.invasionWaves = message.waves;
        this.renderInvasionOverlay();
        return;
      }
      if (message.type === "invasion_state") {
        this.invasion = message.invasion;
        this.requestInvasionWaves(message.invasion.id);
        this.renderInvasionOverlay();
        return;
      }
      if (message.type === "invasion_operation_ok") {
        this.statusText?.setText("INVASION COMMAND ACCEPTED");
        this.refreshInvasions();
        return;
      }
      if (message.type === "player_state") {
        this.player = message.state;
        this.renderPlayer();
        this.updateHud();
        this.requestChunks();
        return;
      }
      if (message.type === "craft_result" || message.type === "shop_purchase_result") {
        this.player = message.state;
        this.renderPlayer();
        this.updateHud();
        this.statusText?.setText(message.type === "craft_result" ? "CRAFT COMPLETE" : "PURCHASE COMPLETE");
        return;
      }
      if (message.type === "trade_result") {
        this.statusText?.setText("TRADE COMPLETE");
        return;
      }
      if (message.type === "world_chunk") {
        this.chunks.render(message.chunk);
        this.updateHud();
        return;
      }
      if (message.type === "creature_party") {
        this.ownedCreatures.clear();
        for (const creature of message.creatures) this.ownedCreatures.set(creature.id, creature);
        return;
      }
      if (message.type === "creature_state") {
        this.ownedCreatures.set(message.creature.id, message.creature);
        if (message.requestId) {
          const targetId = this.pendingCaptureTargets.get(message.requestId);
          if (targetId) {
            this.chunks.removeCreature(targetId);
            this.pendingCaptureTargets.delete(message.requestId);
          }
        }
        if (message.creature.tameProgress >= 100 && message.creature.partySlot === null) {
          this.combatText?.setText(message.creature.species.toUpperCase() + " TAMED • P: PARTY");
        }
        this.combatText?.setText(message.creature.tameProgress >= 100 ? `${message.creature.species.toUpperCase()} TAMED` : `${message.creature.species.toUpperCase()} TAME ${message.creature.tameProgress}%`);
        return;
      }
      if (message.type === "projectile_spawn") {
        this.renderProjectile(message);
        return;
      }
      if (message.type === "combat_result") {
        const projectileId = this.projectileByRequest.get(message.requestId);
        if (projectileId) {
          this.projectiles.get(projectileId)?.destroy();
          this.projectiles.delete(projectileId);
          this.projectileByRequest.delete(message.requestId);
        }
        if (message.killed) this.chunks.removeCreature(message.targetId);
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
      this.invasionWaves = [];
      this.pendingCaptureTargets.clear();
      this.renderInvasionOverlay();
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

  private requestArmies(): void {
    if (this.socket?.readyState !== WebSocket.OPEN) return;
    this.socket.send(JSON.stringify({ type: "list_armies", requestId: this.nextAttackRequestId() }));
  }

  private refreshInvasions(): void {
    if (this.socket?.readyState !== WebSocket.OPEN) return;
    this.requestArmies();
    this.socket.send(JSON.stringify({ type: "list_invasions", requestId: this.nextAttackRequestId(), territoryId: null }));
  }

  private requestInvasionWaves(invasionId: string): void {
    if (this.socket?.readyState !== WebSocket.OPEN) return;
    this.socket.send(JSON.stringify({ type: "get_invasion_waves", requestId: this.nextAttackRequestId(), invasionId }));
  }

  private createInvasionOverlay(): void {
    this.invasionPanel = this.add.rectangle(0, 0, 390, 190, 0x07131f, 0.94).setOrigin(0, 0).setScrollFactor(0).setDepth(1100);
    this.invasionTitle = this.add.text(0, 0, "TACTICAL DEFENSE", { fontFamily: "sans-serif", fontSize: "18px", color: "#ffffff" }).setScrollFactor(0).setDepth(1101);
    this.invasionInfo = this.add.text(0, 0, "No active invasion", { fontFamily: "sans-serif", fontSize: "14px", color: "#ffffff" }).setScrollFactor(0).setDepth(1101);
    this.invasionWaveInfo = this.add.text(0, 0, "", { fontFamily: "sans-serif", fontSize: "13px", color: "#ffffff" }).setScrollFactor(0).setDepth(1101);
    this.invasionRoleText = this.add.text(0, 0, "ROLE: DAMAGE", { fontFamily: "sans-serif", fontSize: "13px", color: "#ffffff" }).setScrollFactor(0).setDepth(1101);
    const button = (label: string, onDown: () => void): Phaser.GameObjects.Text => {
      const text = this.add.text(0, 0, label, { fontFamily: "sans-serif", fontSize: "13px", color: "#ffffff", backgroundColor: "#17314d", padding: { left: 8, right: 8, top: 7, bottom: 7 } })
        .setScrollFactor(0).setDepth(1102).setInteractive({ useHandCursor: true });
      text.on("pointerdown", onDown);
      return text;
    };
    this.invasionJoinButton = button("JOIN", () => this.joinInvasion());
    this.invasionRoleButton = button("ROLE", () => this.cycleInvasionRole());
    this.invasionAttackButton = button("ATTACK", () => this.invasionAction("attack"));
    this.invasionReinforceButton = button("REINFORCE", () => this.invasionAction("reinforce"));
    this.invasionRetreatButton = button("RETREAT", () => this.invasionAction("retreat"));
    this.renderInvasionOverlay();
  }

  private layoutInvasionOverlay(): void {
    if (!this.invasionPanel || !this.invasionTitle || !this.invasionInfo || !this.invasionWaveInfo || !this.invasionRoleText ||
      !this.invasionJoinButton || !this.invasionRoleButton || !this.invasionAttackButton || !this.invasionReinforceButton || !this.invasionRetreatButton) return;
    const width = Math.min(420, Math.max(280, this.scale.width - 16));
    const x = this.scale.width >= 720 ? this.scale.width - width - 8 : 8;
    const y = this.scale.width >= 720 ? 120 : 132;
    this.invasionPanel.setPosition(x, y).setSize(width, 190);
    this.invasionTitle.setPosition(x + 12, y + 9);
    this.invasionInfo.setPosition(x + 12, y + 36);
    this.invasionWaveInfo.setPosition(x + 12, y + 62);
    this.invasionRoleText.setPosition(x + 12, y + 88);
    const buttons = [this.invasionJoinButton, this.invasionRoleButton, this.invasionAttackButton, this.invasionReinforceButton, this.invasionRetreatButton];
    let bx = x + 10;
    for (const item of buttons) {
      item.setPosition(bx, y + 130);
      bx += item.width + 7;
      if (bx > x + width - 90) bx = x + 10;
    }
  }

  private renderInvasionOverlay(): void {
    if (!this.invasionPanel || !this.invasionTitle || !this.invasionInfo || !this.invasionWaveInfo || !this.invasionRoleText ||
      !this.invasionJoinButton || !this.invasionRoleButton || !this.invasionAttackButton || !this.invasionReinforceButton || !this.invasionRetreatButton) return;
    const role = (["tank","damage","support","scout","commander","logistics"] as InvasionRole[])[this.invasionRoleIndex] ?? "damage";
    this.invasionTitle.setText(this.invasion ? "TACTICAL DEFENSE • " + this.invasion.sourceType.toUpperCase() : "TACTICAL DEFENSE");
    this.invasionInfo.setText(this.invasion
      ? this.invasion.phase + " • THREAT " + this.invasion.threatScore + (this.invasion.outcome ? " • " + this.invasion.outcome.toUpperCase() : "")
      : "No active invasion");
    const activeWave = this.invasionWaves.find((wave) => wave.status === "active");
    this.invasionWaveInfo.setText(activeWave
      ? "WAVE " + activeWave.wave_number + " • HP " + activeWave.current_health + "/" + activeWave.max_health + " • AGGRO " + activeWave.aggro_range +
        (activeWave.target_user_id ? " • TARGET LOCKED" : "")
      : this.invasion ? "No active wave • " + this.invasion.phase : "");
    this.invasionRoleText.setText("ROLE: " + role.toUpperCase() + " • ARMIES: " + this.availableArmies.length);
    const battle = this.invasion?.phase === "BATTLE";
    this.invasionJoinButton.setAlpha(this.invasion && this.invasion.phase !== "COMPLETE" ? 1 : 0.45);
    this.invasionRoleButton.setAlpha(this.invasion ? 1 : 0.45);
    this.invasionAttackButton.setAlpha(battle && activeWave ? 1 : 0.45);
    this.invasionReinforceButton.setAlpha(battle ? 1 : 0.45);
    this.invasionRetreatButton.setAlpha(battle ? 1 : 0.45);
    this.layoutInvasionOverlay();
  }

  private cycleInvasionRole(): void {
    this.invasionRoleIndex = (this.invasionRoleIndex + 1) % 6;
    this.renderInvasionOverlay();
  }

  private joinInvasion(): void {
    if (!this.invasion || this.invasion.phase === "COMPLETE" || this.socket?.readyState !== WebSocket.OPEN) return;
    const army = this.availableArmies.find((item) => item.assignment !== "invasion") ?? this.availableArmies[0];
    if (!army) {
      this.statusText?.setText("NO ARMY AVAILABLE");
      return;
    }
    const roles: InvasionRole[] = ["tank","damage","support","scout","commander","logistics"];
    const role = roles[this.invasionRoleIndex] ?? "damage";
    this.socket.send(JSON.stringify({
      type: "join_invasion",
      requestId: this.nextAttackRequestId(),
      invasionId: this.invasion.id,
      armyId: army.id,
      role,
    }));
  }

  private invasionAction(action: "attack" | "reinforce" | "retreat"): void {
    if (!this.invasion || this.invasion.phase !== "BATTLE" || this.socket?.readyState !== WebSocket.OPEN) return;
    const waveId = this.invasionWaves.find((wave) => wave.status === "active")?.id ?? null;
    this.socket.send(JSON.stringify({
      type: "invasion_action",
      requestId: this.nextAttackRequestId(),
      invasionId: this.invasion.id,
      action,
      waveId,
    }));
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
    makeButton("CAPTURE", 310, 650, () => this.captureNearest());
    makeButton("TAME", 410, 650, () => this.tameSelected());
    makeButton("PARTY", 490, 650, () => this.togglePartySelected());
    makeButton("AI", 570, 650, () => this.cycleSelectedAi());
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

  public craftRecipe(recipeId: string): void {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;
    this.socket.send(JSON.stringify({ type: "craft", requestId: this.nextAttackRequestId(), recipeId }));
  }

  public purchaseShopItem(itemId: string, quantity: number): void {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;
    if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 100) return;
    this.socket.send(JSON.stringify({ type: "shop_purchase", requestId: this.nextAttackRequestId(), itemId, quantity }));
  }

  public tradePlayer(toUserId: string, gold: string, items: Array<{ itemId: string; quantity: number }>): void {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;
    if (typeof toUserId !== "string" || toUserId.length === 0 || toUserId.length > 64 || typeof gold !== "string" || gold.length === 0 || gold.length > 32 || items.length > 32) return;
    this.socket.send(JSON.stringify({ type: "trade", requestId: this.nextAttackRequestId(), toUserId, gold, items }));
  }

  private captureNearest(): void {
    if (!this.player || this.socket?.readyState !== WebSocket.OPEN) return;
    const target = this.chunks.nearestCreature(this.player.x, this.player.y, 2.5);
    if (!target) { this.combatText?.setText("NO CREATURE IN CAPTURE RANGE"); return; }
    const requestId = this.nextAttackRequestId();
    this.pendingCaptureTargets.set(requestId, target.id);
    this.socket.send(JSON.stringify({ type: "capture", requestId, targetId: target.id }));
  }

  private tameSelected(): void {
    if (this.socket?.readyState !== WebSocket.OPEN) return;
    const creature = [...this.ownedCreatures.values()].find((x) => x.partySlot !== null) ?? [...this.ownedCreatures.values()][0];
    if (!creature) { this.combatText?.setText("NO OWNED CREATURE"); return; }
    this.socket.send(JSON.stringify({ type: "tame", requestId: this.nextAttackRequestId(), creatureId: creature.id }));
  }


  private selectedOwnedCreature(): CreatureState | undefined {
    return [...this.ownedCreatures.values()].find((x) => x.partySlot !== null) ?? [...this.ownedCreatures.values()][0];
  }

  private togglePartySelected(): void {
    if (this.socket?.readyState !== WebSocket.OPEN) return;
    const creature = this.selectedOwnedCreature();
    if (!creature || creature.tameProgress < 100) {
      this.combatText?.setText("CREATURE MUST BE FULLY TAMED");
      return;
    }
    const slot = creature.partySlot === null ? 0 : null;
    this.socket.send(JSON.stringify({ type: "set_creature_party", requestId: this.nextAttackRequestId(), creatureId: creature.id, slot }));
  }

  private cycleSelectedAi(): void {
    if (this.socket?.readyState !== WebSocket.OPEN) return;
    const creature = this.selectedOwnedCreature();
    if (!creature || creature.tameProgress < 100) {
      this.combatText?.setText("CREATURE MUST BE FULLY TAMED");
      return;
    }
    const modes: CreatureState["aiMode"][] = ["follow", "assist", "stay"];
    const mode = modes[(modes.indexOf(creature.aiMode) + 1) % modes.length] ?? "follow";
    this.socket.send(JSON.stringify({ type: "set_creature_ai", requestId: this.nextAttackRequestId(), creatureId: creature.id, mode }));
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
