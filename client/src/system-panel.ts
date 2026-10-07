import type Phaser from "phaser";
import type { ServerMessage } from "./network.js";

type SendMessage = (message: Record<string, unknown>) => void;
type PlayerPosition = () => { x: number; y: number } | null;

type Action = { label: string; run: () => void };

const categories = ["SOCIAL", "GUILD", "BASE", "BREEDING", "SHIPS", "REALMS", "AUCTION", "WORLD", "STRATEGY", "ENDGAME", "CRAFT"] as const;
type Category = typeof categories[number];

export class SystemPanel {
  private readonly toggle: Phaser.GameObjects.Text;
  private readonly panel: Phaser.GameObjects.Rectangle;
  private readonly title: Phaser.GameObjects.Text;
  private readonly result: Phaser.GameObjects.Text;
  private readonly categoryButtons: Phaser.GameObjects.Text[] = [];
  private readonly actionButtons: Phaser.GameObjects.Text[] = [];
  private category: Category = "SOCIAL";
  private open = false;
  private readonly pending = new Set<string>();

  constructor(
    private readonly scene: Phaser.Scene,
    private readonly send: SendMessage,
    private readonly playerPosition: PlayerPosition,
  ) {
    this.toggle = scene.add.text(0, 0, "SYSTEMS", this.buttonStyle()).setScrollFactor(0).setDepth(1300).setInteractive({ useHandCursor: true });
    this.toggle.on("pointerdown", () => this.setOpen(!this.open));
    this.panel = scene.add.rectangle(0, 0, 620, 520, 0x07131f, 0.97).setOrigin(0).setScrollFactor(0).setDepth(1290);
    this.title = scene.add.text(0, 0, "SYSTEMS", { fontFamily: "sans-serif", fontSize: "18px", color: "#ffffff" }).setScrollFactor(0).setDepth(1301);
    this.result = scene.add.text(0, 0, "Select a system.", {
      fontFamily: "monospace", fontSize: "12px", color: "#ffffff", wordWrap: { width: 580 },
    }).setScrollFactor(0).setDepth(1301);
    for (const category of categories) {
      const button = scene.add.text(0, 0, category, this.buttonStyle()).setScrollFactor(0).setDepth(1301).setInteractive({ useHandCursor: true });
      button.on("pointerdown", () => { this.category = category; this.render(); });
      this.categoryButtons.push(button);
    }
    this.setOpen(false);
    this.render();
    this.layout();
    scene.scale.on("resize", () => this.layout());
  }

  handleMessage(message: ServerMessage): void {
    const requestId = "requestId" in message && typeof message.requestId === "string" ? message.requestId : undefined;
    if (!requestId || !this.pending.has(requestId)) return;
    this.pending.delete(requestId);
    this.result.setText(JSON.stringify(message, null, 2).slice(0, 6000));
  }

  private buttonStyle(): Phaser.Types.GameObjects.Text.TextStyle {
    return { fontFamily: "sans-serif", fontSize: "12px", color: "#ffffff", backgroundColor: "#17314dcc", padding: { left: 7, right: 7, top: 6, bottom: 6 } };
  }

  private prompt(label: string): string | null {
    const value = window.prompt(label);
    return value === null ? null : value.trim();
  }

  private request(type: string, payload: Record<string, unknown> = {}): void {
    const requestId = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8);
    this.pending.add(requestId);
    this.send({ type, requestId, ...payload });
  }

  private actions(): Action[] {
    const ask = (label: string, type: string, payload: Record<string, unknown> = {}): Action => ({ label, run: () => this.request(type, payload) });
    if (this.category === "SOCIAL") return [
      ask("FRIENDS", "list_friends"), ask("BLOCKS", "list_blocks"), ask("PARTY", "get_party"), ask("INVITES", "party_invitations"),
      { label: "ADD FRIEND", run: () => { const id = this.prompt("Target user ID"); if (id) this.request("add_friend", { targetUserId: id }); } },
      { label: "REMOVE FRIEND", run: () => { const id = this.prompt("Target user ID"); if (id) this.request("remove_friend", { targetUserId: id }); } },
      { label: "CHAT", run: () => this.request("chat_history", { channel: "global", recipientUserId: null, guildId: null, partyId: null }) },
      { label: "SEND CHAT", run: () => { const body = this.prompt("Global chat message"); if (body) this.request("chat_send", { channel: "global", body, recipientUserId: null, guildId: null, partyId: null }); } },
      ask("CREATE PARTY", "create_party"),
      { label: "PARTY INVITE", run: () => { const id = this.prompt("Target user ID"); if (id) this.request("party_invite", { targetUserId: id }); } },
      ask("LEAVE PARTY", "party_leave"),
    ];
    if (this.category === "GUILD") return [
      ask("MY GUILD", "get_guild"), ask("INVITES", "list_guild_invitations"),
      { label: "CREATE", run: () => { const name = this.prompt("Guild name"); const tag = this.prompt("Guild tag"); if (name && tag) this.request("create_guild", { name, tag }); } },
      { label: "INVITE", run: () => { const guildId = this.prompt("Guild ID"); const targetUserId = this.prompt("Target user ID"); if (guildId && targetUserId) this.request("invite_guild_member", { guildId, targetUserId }); } },
      { label: "BANK", run: () => { const guildId = this.prompt("Guild ID"); if (guildId) this.request("guild_bank", { guildId }); } },
      { label: "LEAVE", run: () => { const guildId = this.prompt("Guild ID"); if (guildId) this.request("leave_guild", { guildId }); } },
      { label: "BUILD INFRA", run: () => { const guildId = this.prompt("Guild ID"); const structureType = this.prompt("Structure type"); if (guildId && structureType) this.request("build_guild_infrastructure", { guildId, structureType }); } },
    ];
    if (this.category === "BASE") return [
      { label: "CREATE BASE", run: () => { const position = this.playerPosition(); const name = this.prompt("Base name"); if (name && position) this.request("create_base", { name, x: Math.round(position.x), y: Math.round(position.y) }); } },
      { label: "DEFENSES", run: () => { const baseId = this.prompt("Base ID"); if (baseId) this.request("list_defenses", { baseId }); } },
      { label: "BUILD", run: () => { const baseId = this.prompt("Base ID"); const buildingType = this.prompt("Building type"); const level = Number(this.prompt("Level") ?? "1"); const gridX = Number(this.prompt("Grid X") ?? "0"); const gridY = Number(this.prompt("Grid Y") ?? "0"); if (baseId && buildingType && Number.isSafeInteger(level) && Number.isSafeInteger(gridX) && Number.isSafeInteger(gridY)) this.request("build", { baseId, buildingType, level, gridX, gridY }); } },
      { label: "UPGRADE", run: () => { const buildingId = this.prompt("Building ID"); if (buildingId) this.request("upgrade_building", { buildingId }); } },
      { label: "STORAGE", run: () => { const itemId = this.prompt("Item ID"); const delta = Number(this.prompt("Quantity delta")); if (itemId && Number.isSafeInteger(delta)) this.request("storage", { changes: { [itemId]: delta } }); } },
      { label: "WORKER", run: () => { const creatureId = this.prompt("Creature ID"); const buildingId = this.prompt("Building ID"); const task = this.prompt("Task"); if (creatureId && buildingId && task) this.request("assign_worker", { creatureId, buildingId, task }); } },
      { label: "PRIORITIES", run: () => { const value = this.prompt("Priorities, comma separated"); if (value) this.request("set_work_priorities", { priorities: value.split(",").map((x) => x.trim()).filter(Boolean).slice(0, 6) }); } },
    ];
    if (this.category === "BREEDING") return [
      ask("JOBS", "list_breeding"),
      { label: "START", run: () => {
        const baseId = this.prompt("Base ID"); const penBuildingId = this.prompt("Breeding pen ID");
        const parentAId = this.prompt("Parent A creature ID"); const parentBId = this.prompt("Parent B creature ID");
        const durationMs = Number(this.prompt("Duration ms") ?? "3600000");
        if (baseId && penBuildingId && parentAId && parentBId && Number.isSafeInteger(durationMs)) this.request("start_breeding", { baseId, penBuildingId, parentAId, parentBId, durationMs });
      } },
    ];
    if (this.category === "SHIPS") return [
      ask("SHIPS", "list_ships"), ask("FLEETS", "list_fleets"),
      { label: "CREATE SHIP", run: () => { const name = this.prompt("Ship name"); const shipClass = this.prompt("Ship class"); if (name && shipClass) this.request("create_ship", { name, shipClass }); } },
      { label: "SHIP INVENTORY", run: () => { const shipId = this.prompt("Ship ID"); if (shipId) this.request("ship_inventory", { shipId }); } },
      { label: "SAIL", run: () => { const shipId = this.prompt("Ship ID"); const dx = Number(this.prompt("Direction X")); const dy = Number(this.prompt("Direction Y")); const dt = Number(this.prompt("Duration seconds")); if (shipId && Number.isFinite(dx) && Number.isFinite(dy) && Number.isFinite(dt)) this.request("sail", { shipId, dx, dy, dt }); } },
      { label: "REPAIR", run: () => { const shipId = this.prompt("Ship ID"); if (shipId) this.request("repair_ship", { shipId }); } },
      { label: "CREATE FLEET", run: () => { const name = this.prompt("Fleet name"); const shipId = this.prompt("Initial ship ID"); if (name && shipId) this.request("create_fleet", { name, shipId }); } },
    ];
    if (this.category === "REALMS") return [
      ask("REALMS", "list_realms"), ask("TERRITORIES", "list_territories"), ask("FORTRESSES", "list_realm_fortresses"),
      ask("ROUTES", "list_trade_routes"), ask("REPUTATION", "my_realm_reputation"), ask("SEASON", "list_territory_season"),
      { label: "TERRITORY", run: () => { const x = Number(this.prompt("World X")); const y = Number(this.prompt("World Y")); if (Number.isSafeInteger(x) && Number.isSafeInteger(y)) this.request("territory_at", { x, y }); } },
      { label: "TRADE ROUTE", run: () => {
        const sourceTerritoryId = this.prompt("Source territory ID"); const destinationTerritoryId = this.prompt("Destination territory ID");
        const resourceKey = this.prompt("Resource key"); const quantity = this.prompt("Quantity"); const travelSeconds = Number(this.prompt("Travel seconds"));
        if (sourceTerritoryId && destinationTerritoryId && resourceKey && quantity && Number.isSafeInteger(travelSeconds)) this.request("create_trade_route", { sourceTerritoryId, destinationTerritoryId, resourceKey, quantity, travelSeconds, guildId: null, realmId: null });
      } },
    ];
    if (this.category === "AUCTION") return [
      { label: "LIST", run: () => this.request("auction_list", { itemId: null, rarity: null, category: null, minLevel: null, maxLevel: null, minPrice: null, maxPrice: null }) },
      ask("HISTORY", "auction_history"),
      { label: "CREATE", run: () => { const itemId = this.prompt("Item ID"); const quantity = Number(this.prompt("Quantity")); const startPrice = this.prompt("Start price"); const buyNowPrice = this.prompt("Buy-now price (blank for none)"); const durationMs = Number(this.prompt("Duration ms")); if (itemId && Number.isSafeInteger(quantity) && quantity > 0 && startPrice && Number.isSafeInteger(durationMs)) this.request("auction_create", { itemId, quantity, startPrice, buyNowPrice: buyNowPrice || null, durationMs }); } },
      { label: "BID", run: () => { const listingId = this.prompt("Listing ID"); const amount = this.prompt("Bid amount"); if (listingId && amount) this.request("auction_bid", { listingId, amount }); } },
      { label: "BUY NOW", run: () => { const listingId = this.prompt("Listing ID"); if (listingId) this.request("auction_buy_now", { listingId }); } },
      { label: "CANCEL", run: () => { const listingId = this.prompt("Listing ID"); if (listingId) this.request("auction_cancel", { listingId }); } },
    ];
    if (this.category === "WORLD") return [
      ask("EVENTS", "list_world_events"),
      { label: "CONTRIBUTE", run: () => { const eventId = this.prompt("World event ID"); if (eventId) this.request("world_event_contribute", { eventId }); } },
      { label: "REWARD", run: () => { const eventId = this.prompt("World event ID"); if (eventId) this.request("world_event_reward", { eventId }); } },
    ];
    if (this.category === "STRATEGY") return [
      ask("ARMIES", "list_armies"), ask("INVASIONS", "list_invasions", { territoryId: null }), ask("REALM WARS", "list_realm_wars"), ask("GUILD BATTLES", "list_guild_battles"),
      { label: "CREATE ARMY", run: () => { const name = this.prompt("Army name"); if (name) this.request("create_army", { name }); } },
      { label: "TRAIN", run: () => { const armyId = this.prompt("Army ID"); const unitType = this.prompt("Unit type"); const quantity = Number(this.prompt("Quantity")); if (armyId && unitType && Number.isSafeInteger(quantity)) this.request("train_army", { armyId, unitType, quantity }); } },
      { label: "REALM WAR", run: () => { const attackerRealmId = this.prompt("Attacker realm ID"); const defenderRealmId = this.prompt("Defender realm ID"); const targetTerritoryId = this.prompt("Target territory ID"); if (attackerRealmId && defenderRealmId && targetTerritoryId) this.request("create_realm_war", { attackerRealmId, defenderRealmId, targetTerritoryId }); } },
      { label: "GUILD BATTLE", run: () => { const attackerGuildId = this.prompt("Attacker guild ID"); const defenderGuildId = this.prompt("Defender guild ID"); const targetTerritoryId = this.prompt("Target territory ID"); if (attackerGuildId && defenderGuildId && targetTerritoryId) this.request("create_guild_battle", { attackerGuildId, defenderGuildId, targetTerritoryId }); } },
    ];
    if (this.category === "ENDGAME") return [
      ask("ENDGAME CREATURES", "list_endgame_creatures"), ask("MYTHIC CONTENT", "list_mythic_content"),
      { label: "ENGAGE", run: () => { const creatureId = this.prompt("Endgame creature ID"); if (creatureId) this.request("engage_endgame_creature", { creatureId }); } },
    ];
    return [
      { label: "CRAFT", run: () => { const recipeId = this.prompt("Recipe ID"); if (recipeId) this.request("craft", { recipeId }); } },
      { label: "SHOP", run: () => { const itemId = this.prompt("Shop item ID"); const quantity = Number(this.prompt("Quantity")); if (itemId && Number.isSafeInteger(quantity)) this.request("shop_purchase", { itemId, quantity }); } },
      { label: "TRADE", run: () => { const toUserId = this.prompt("Target user ID"); const gold = this.prompt("Gold"); const itemId = this.prompt("Item ID (blank for none)"); const quantity = Number(this.prompt("Quantity")); if (toUserId && gold) this.request("trade", { toUserId, gold, items: itemId ? [{ itemId, quantity: Number.isSafeInteger(quantity) ? quantity : 0 }] : [] }); } },
    ];
  }

  private render(): void {
    this.title.setText("SYSTEMS • " + this.category);
    this.actionButtons.splice(0).forEach((button) => button.destroy());
    const actions = this.actions();
    for (const action of actions) {
      const button = this.scene.add.text(0, 0, action.label, this.buttonStyle()).setScrollFactor(0).setDepth(1302).setInteractive({ useHandCursor: true });
      button.on("pointerdown", action.run);
      this.actionButtons.push(button);
    }
    this.layout();
  }

  private setOpen(open: boolean): void {
    this.open = open;
    this.panel.setVisible(open);
    this.title.setVisible(open);
    this.result.setVisible(open);
    for (const button of this.categoryButtons) button.setVisible(open);
    for (const button of this.actionButtons) button.setVisible(open);
    this.toggle.setText(open ? "CLOSE SYSTEMS" : "SYSTEMS");
    this.layout();
  }

  private layout(): void {
    const width = Math.min(640, Math.max(300, this.scene.scale.width - 16));
    const x = this.scene.scale.width - width - 8;
    const y = 70;
    this.toggle.setPosition(Math.max(8, this.scene.scale.width - this.toggle.width - 8), 12);
    this.panel.setPosition(x, y).setSize(width, Math.min(560, Math.max(430, this.scene.scale.height - 90)));
    this.title.setPosition(x + 12, y + 10);
    let bx = x + 10;
    let by = y + 42;
    for (const button of this.categoryButtons) {
      button.setPosition(bx, by);
      bx += button.width + 5;
      if (bx > x + width - 90) { bx = x + 10; by += 34; }
    }
    by += 38;
    let ax = x + 10;
    for (const button of this.actionButtons) {
      button.setPosition(ax, by);
      ax += button.width + 5;
      if (ax > x + width - 100) { ax = x + 10; by += 34; }
    }
    this.result.setPosition(x + 12, by + 42).setWordWrapWidth(width - 24);
  }
}
