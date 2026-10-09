import type Phaser from "phaser";
import type { ServerMessage } from "./network.js";
import type { PlayerState } from "./player.js";
import { firstEndgameCreatureId, firstMythicContentKey, selectedCreatureEngagement } from "./endgame-selection.js";

type SendMessage = (message: Record<string, unknown>) => void;
type PlayerPosition = () => { x: number; y: number } | null;
type PlayerStateReader = () => PlayerState | null;

type Action = { label: string; run: () => void };
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
const RECIPES = [
  ["tool.wooden-club", "Wooden Club", "8 Wood → 1 Club"],
  ["tool.stone-axe", "Stone Axe", "6 Wood + 4 Stone → 1 Axe"],
  ["tool.stone-pickaxe", "Stone Pickaxe", "6 Wood + 5 Stone → 1 Pickaxe"],
  ["structure.campfire", "Campfire", "8 Wood + 4 Stone → 1 Campfire"],
  ["structure.wooden-wall", "Wooden Wall", "10 Wood → 1 Wall"],
  ["consumable.herb-bandage", "Herb Bandage", "3 Herb → 1 Bandage"],
] as const;
const SHOP = [
  ["resource.wood", "Wood Bundle", "10"],
  ["resource.stone", "Stone Bundle", "15"],
  ["resource.iron", "Iron Ore Bundle", "25"],
  ["resource.herb", "Herb Bundle", "12"],
  ["upgrade.camp.tier2", "Camp Tier II", "500"],
  ["upgrade.storage.tier2", "Storage Tier II", "350"],
  ["upgrade.forge.tier2", "Forge Tier II", "450"],
  ["defence.wall.segment", "Defensive Wall", "40"],
  ["defence.cannon", "Defensive Cannon", "250"],
  ["defence.watchtower", "Watchtower", "400"],
] as const;

const categories = ["INVENTORY", "CRAFT", "SHOP", "TRADE", "SOCIAL", "GUILD", "BASE", "BREEDING", "SHIPS", "REALMS", "AUCTION", "WORLD", "STRATEGY", "ENDGAME"] as const;
type Category = typeof categories[number];

export class SystemPanel {
  private readonly toggle: Phaser.GameObjects.Text;
  private readonly panel: Phaser.GameObjects.Rectangle;
  private readonly title: Phaser.GameObjects.Text;
  private readonly result: Phaser.GameObjects.Text;
  private readonly categoryButtons: Phaser.GameObjects.Text[] = [];
  private readonly actionButtons: Phaser.GameObjects.Text[] = [];
  private category: Category = "INVENTORY";
  private selectedTradeTarget?: string;
  private selectedGuildId?: string;
  private selectedGuildInvitationId?: string;
  private selectedBaseId?: string;
  private selectedShipId?: string;
  private selectedFleetId?: string;
  private selectedAuctionListingId?: string;
  private selectedWorldEventId?: string;
  private selectedArmyId?: string;
  private selectedEndgameCreatureId?: string;
  private selectedMythicContentId?: string;
  private open = false;
  private readonly pending = new Set<string>();

  constructor(
    private readonly scene: Phaser.Scene,
    private readonly send: SendMessage,
    private readonly playerPosition: PlayerPosition,
    private readonly playerState: PlayerStateReader,
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
    if (message.type === "friends_list") {
      const first = message.friends[0];
      const target = first && typeof first === "object" && "userId" in first && typeof first.userId === "string" ? first.userId : undefined;
      this.selectedTradeTarget = target;
      this.result.setText(target ? "Selected friend: " + target : "No friends available.");
      return;
    }
    if (message.type === "guild_state") {
      if (isRecord(message.guild) && typeof message.guild.id === "string") this.selectedGuildId = message.guild.id;
      this.result.setText(this.selectedGuildId ? "Guild selected: " + this.selectedGuildId : "No active guild.");
      return;
    }
    if (message.type === "guild_invitations") {
      const first = isRecord(message.invitations) ? message.invitations["0"] : undefined;
      this.selectedGuildInvitationId = isRecord(first) && typeof first.id === "string" ? first.id : undefined;
      this.result.setText(this.selectedGuildInvitationId ? "Invitation selected." : "No guild invitations.");
      return;
    }
    if (message.type === "endgame_creature_list") {
      this.selectedEndgameCreatureId = firstEndgameCreatureId(message.creatures);
      this.result.setText(this.selectedEndgameCreatureId ? "Endgame creature selected: " + this.selectedEndgameCreatureId : "No endgame creatures available.");
      return;
    }
    if (message.type === "mythic_content_list") {
      this.selectedMythicContentId = firstMythicContentKey(message.content);
      this.result.setText(this.selectedMythicContentId ? "Mythic content selected (information only): " + this.selectedMythicContentId : "No mythic content available.");
      return;
    }
    if (message.type === "army_list") {
      const first = isRecord(message.armies) ? message.armies["0"] : undefined;
      this.selectedArmyId = isRecord(first) && typeof first.id === "string" ? first.id : undefined;
      this.result.setText(this.selectedArmyId ? "Army selected: " + this.selectedArmyId : "No armies available.");
      return;
    }
    if (message.type === "auction_list") {
      const first = isRecord(message.listings) ? message.listings["0"] : undefined;
      this.selectedAuctionListingId = isRecord(first) && typeof first.id === "string" ? first.id : undefined;
      this.result.setText(this.selectedAuctionListingId ? "Auction listing selected: " + this.selectedAuctionListingId : "No auction listings.");
      return;
    }
    if (message.type === "world_event_list") {
      const first = isRecord(message.events) ? message.events["0"] : undefined;
      this.selectedWorldEventId = isRecord(first) && typeof first.id === "string" ? first.id : undefined;
      this.result.setText(this.selectedWorldEventId ? "World event selected: " + this.selectedWorldEventId : "No active world events.");
      return;
    }
    if (message.type === "ship_list") {
      const first = isRecord(message.ships) ? message.ships["0"] : undefined;
      this.selectedShipId = isRecord(first) && typeof first.id === "string" ? first.id : undefined;
      this.result.setText(this.selectedShipId ? "Ship selected: " + this.selectedShipId : "No ships available.");
      return;
    }
    if (message.type === "fleet_list") {
      const first = isRecord(message.fleets) ? message.fleets["0"] : undefined;
      this.selectedFleetId = isRecord(first) && typeof first.id === "string" ? first.id : undefined;
      this.result.setText(this.selectedFleetId ? "Fleet selected: " + this.selectedFleetId : "No fleets available.");
      return;
    }
    if (message.type === "base_state") {
      if (isRecord(message.base) && typeof message.base.id === "string") this.selectedBaseId = message.base.id;
      this.result.setText(this.selectedBaseId ? "Base selected: " + this.selectedBaseId : "No active base.");
      return;
    }
    if (message.type === "player_state") {
      const inventory = message.state.inventory;
      const lines = Object.entries(inventory).filter(([, quantity]) => quantity > 0).map(([item, quantity]) => item + " × " + quantity);
      this.result.setText("INVENTORY\nGold: " + message.state.gold + "\nBadges: " + message.state.triumphBadges + "\n" + (lines.length ? lines.join("\n") : "Empty"));
      return;
    }
    if (message.type === "craft_result" || message.type === "shop_purchase_result" || message.type === "trade_result") {
      this.result.setText(JSON.stringify(message, null, 2).slice(0, 6000));
      return;
    }
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
    if (this.category === "INVENTORY") {
      return [];
    }
    if (this.category === "CRAFT") return RECIPES.map(([id, name, ingredients]) => ({
      label: name + " • " + ingredients,
      run: () => this.request("craft", { recipeId: id }),
    }));
    if (this.category === "SHOP") return SHOP.map(([id, name, price]) => ({
      label: name + " • " + price + " GOLD",
      run: () => this.request("shop_purchase", { itemId: id, quantity: 1 }),
    }));
    if (this.category === "TRADE") return [
      { label: "LOAD FRIENDS", run: () => this.request("list_friends") },
      { label: "SELECTED FRIEND", run: () => {
        this.result.setText(this.selectedTradeTarget ? "Selected trade target: " + this.selectedTradeTarget : "Load friends first.");
      } },
    ];
    if (this.category === "SOCIAL") return [
      ask("LOAD FRIENDS", "list_friends"),
      ask("BLOCKS", "list_blocks"),
      ask("PARTY", "get_party"),
      ask("INVITES", "party_invitations"),
      { label: "ADD SELECTED", run: () => { if (this.selectedTradeTarget) this.request("add_friend", { targetUserId: this.selectedTradeTarget }); } },
      { label: "REMOVE SELECTED", run: () => { if (this.selectedTradeTarget) this.request("remove_friend", { targetUserId: this.selectedTradeTarget }); } },
      { label: "BLOCK SELECTED", run: () => { if (this.selectedTradeTarget) this.request("block_user", { targetUserId: this.selectedTradeTarget }); } },
      { label: "CHAT HISTORY", run: () => this.request("chat_history", { channel: "global", recipientUserId: null, guildId: null, partyId: null }) },
      ask("CREATE PARTY", "create_party"),
      { label: "INVITE SELECTED", run: () => { if (this.selectedTradeTarget) this.request("party_invite", { targetUserId: this.selectedTradeTarget }); } },
      ask("LEAVE PARTY", "party_leave"),
    ];
    if (this.category === "GUILD") return [
      ask("MY GUILD", "get_guild"),
      ask("INVITES", "list_guild_invitations"),
      { label: "ACCEPT SELECTED", run: () => { if (this.selectedGuildInvitationId) this.request("accept_guild_invite", { invitationId: this.selectedGuildInvitationId }); } },
      { label: "BANK", run: () => { if (this.selectedGuildId) this.request("guild_bank", { guildId: this.selectedGuildId }); } },
      { label: "LEAVE GUILD", run: () => { if (this.selectedGuildId) this.request("leave_guild", { guildId: this.selectedGuildId }); } },
      { label: "BUILD INFRA", run: () => {
        const structureType = this.prompt("Structure type");
        if (this.selectedGuildId && structureType) this.request("build_guild_infrastructure", { guildId: this.selectedGuildId, structureType });
      } },
      { label: "CREATE GUILD", run: () => {
        const name = this.prompt("Guild name"); const tag = this.prompt("Guild tag");
        if (name && tag) this.request("create_guild", { name, tag });
      } },
    ];
    if (this.category === "BASE") return [
      { label: "CREATE BASE", run: () => { const position = this.playerPosition(); const name = this.prompt("Base name"); if (name && position) this.request("create_base", { name, x: Math.round(position.x), y: Math.round(position.y) }); } },
      { label: "DEFENSES", run: () => { if (this.selectedBaseId) this.request("list_defenses", { baseId: this.selectedBaseId }); } },
      { label: "BUILD", run: () => { const buildingType = this.prompt("Building type"); const level = Number(this.prompt("Level") ?? "1"); const gridX = Number(this.prompt("Grid X") ?? "0"); const gridY = Number(this.prompt("Grid Y") ?? "0"); if (this.selectedBaseId && buildingType && Number.isSafeInteger(level) && Number.isSafeInteger(gridX) && Number.isSafeInteger(gridY)) this.request("build", { baseId: this.selectedBaseId, buildingType, level, gridX, gridY }); } },
      { label: "UPGRADE", run: () => { const buildingId = this.prompt("Building ID"); if (buildingId) this.request("upgrade_building", { buildingId }); } },
      { label: "STORAGE", run: () => { const itemId = this.prompt("Item ID"); const delta = Number(this.prompt("Quantity delta")); if (itemId && Number.isSafeInteger(delta)) this.request("storage", { changes: { [itemId]: delta } }); } },
      { label: "WORKER", run: () => { const creatureId = this.prompt("Creature ID"); const buildingId = this.prompt("Building ID"); const task = this.prompt("Task"); if (creatureId && buildingId && task) this.request("assign_worker", { creatureId, buildingId, task }); } },
      { label: "PRIORITIES", run: () => { const value = this.prompt("Priorities, comma separated"); if (value) this.request("set_work_priorities", { priorities: value.split(",").map((x) => x.trim()).filter(Boolean).slice(0, 6) }); } },
    ];
    if (this.category === "BREEDING") return [
      ask("JOBS", "list_breeding"),
      { label: "START", run: () => {
        const baseId = this.selectedBaseId; const penBuildingId = this.prompt("Breeding pen ID");
        const parentAId = this.prompt("Parent A creature ID"); const parentBId = this.prompt("Parent B creature ID");
        const durationMs = Number(this.prompt("Duration ms") ?? "3600000");
        if (baseId && penBuildingId && parentAId && parentBId && Number.isSafeInteger(durationMs)) this.request("start_breeding", { baseId, penBuildingId, parentAId, parentBId, durationMs });
      } },
    ];
    if (this.category === "SHIPS") return [
      ask("LOAD SHIPS", "list_ships"), ask("LOAD FLEETS", "list_fleets"),
      { label: "CREATE SHIP", run: () => { const name = this.prompt("Ship name"); const shipClass = this.prompt("Ship class"); if (name && shipClass) this.request("create_ship", { name, shipClass }); } },
      { label: "SHIP INVENTORY", run: () => { if (this.selectedShipId) this.request("ship_inventory", { shipId: this.selectedShipId }); } },
      { label: "CARGO", run: () => { const itemId = this.prompt("Item ID"); const quantity = Number(this.prompt("Quantity")); if (this.selectedShipId && itemId && Number.isSafeInteger(quantity)) this.request("ship_cargo", { shipId: this.selectedShipId, itemId, quantity }); } },
      { label: "CREW", run: () => { const creatureId = this.prompt("Creature ID"); const role = this.prompt("Crew role"); const skill = Number(this.prompt("Skill")); const morale = Number(this.prompt("Morale")); if (this.selectedShipId && creatureId && role && Number.isSafeInteger(skill) && Number.isSafeInteger(morale)) this.request("assign_ship_crew", { shipId: this.selectedShipId, creatureId, role, skill, morale }); } },
      { label: "SAIL", run: () => { const dx = Number(this.prompt("Direction X")); const dy = Number(this.prompt("Direction Y")); const dt = Number(this.prompt("Duration seconds")); if (this.selectedShipId && Number.isFinite(dx) && Number.isFinite(dy) && Number.isFinite(dt)) this.request("sail", { shipId: this.selectedShipId, dx, dy, dt }); } },
      { label: "REPAIR", run: () => { if (this.selectedShipId) this.request("repair_ship", { shipId: this.selectedShipId }); } },
      { label: "CANNON", run: () => { const targetShipId = this.prompt("Target ship ID"); if (this.selectedShipId && targetShipId) this.request("fire_cannon", { shipId: this.selectedShipId, targetShipId }); } },
      { label: "BOARD", run: () => { const targetShipId = this.prompt("Target ship ID"); if (this.selectedShipId && targetShipId) this.request("board_ship", { shipId: this.selectedShipId, targetShipId }); } },
      { label: "RETREAT", run: () => { if (this.selectedShipId) this.request("retreat_ship", { shipId: this.selectedShipId }); } },
      { label: "CREATE FLEET", run: () => { const name = this.prompt("Fleet name"); if (name && this.selectedShipId) this.request("create_fleet", { name, shipId: this.selectedShipId }); } },
    ];
    if (this.category === "REALMS") return [
      ask("REALMS", "list_realms"), ask("TERRITORIES", "list_territories"), ask("FORTRESSES", "list_realm_fortresses"),
      ask("ROUTES", "list_trade_routes"), ask("REPUTATION", "my_realm_reputation"), ask("SEASON", "list_territory_season"),
      { label: "TERRITORY", run: () => { const x = Number(this.prompt("World X")); const y = Number(this.prompt("World Y")); if (Number.isSafeInteger(x) && Number.isSafeInteger(y)) this.request("territory_at", { x, y }); } },
      { label: "CLAIM", run: () => { const territoryId = this.prompt("Territory ID"); const guildId = this.prompt("Guild ID"); if (territoryId && guildId) this.request("claim_guild_territory", { territoryId, guildId }); } },
      { label: "REPUTATION", run: () => { const realm = this.prompt("Realm"); const delta = Number(this.prompt("Reputation delta")); if (realm && Number.isSafeInteger(delta)) this.request("change_realm_reputation", { realm, delta }); } },
      ask("REALM AI TICK", "tick_realm_ai"),
      { label: "TRADE ROUTE", run: () => {
        const sourceTerritoryId = this.prompt("Source territory ID"); const destinationTerritoryId = this.prompt("Destination territory ID");
        const resourceKey = this.prompt("Resource key"); const quantity = this.prompt("Quantity"); const travelSeconds = Number(this.prompt("Travel seconds"));
        if (sourceTerritoryId && destinationTerritoryId && resourceKey && quantity && Number.isSafeInteger(travelSeconds)) this.request("create_trade_route", { sourceTerritoryId, destinationTerritoryId, resourceKey, quantity, travelSeconds, guildId: null, realmId: null });
      } },
    ];
    if (this.category === "AUCTION") return [
      { label: "LOAD LISTINGS", run: () => this.request("auction_list", { itemId: null, rarity: null, category: null, minLevel: null, maxLevel: null, minPrice: null, maxPrice: null }) },
      ask("HISTORY", "auction_history"),
      { label: "CREATE", run: () => { const itemId = this.prompt("Item ID"); const quantity = Number(this.prompt("Quantity")); const startPrice = this.prompt("Start price"); const buyNowPrice = this.prompt("Buy-now price (blank for none)"); const durationMs = Number(this.prompt("Duration ms")); if (itemId && Number.isSafeInteger(quantity) && quantity > 0 && startPrice && Number.isSafeInteger(durationMs)) this.request("auction_create", { itemId, quantity, startPrice, buyNowPrice: buyNowPrice || null, durationMs }); } },
      { label: "BID SELECTED", run: () => { const amount = this.prompt("Bid amount"); if (this.selectedAuctionListingId && amount) this.request("auction_bid", { listingId: this.selectedAuctionListingId, amount }); } },
      { label: "BUY SELECTED", run: () => { if (this.selectedAuctionListingId) this.request("auction_buy_now", { listingId: this.selectedAuctionListingId }); } },
      { label: "CANCEL SELECTED", run: () => { if (this.selectedAuctionListingId) this.request("auction_cancel", { listingId: this.selectedAuctionListingId }); } },
    ];
    if (this.category === "WORLD") return [
      ask("LOAD EVENTS", "list_world_events"),
      { label: "CONTRIBUTE SELECTED", run: () => { if (this.selectedWorldEventId) this.request("world_event_contribute", { eventId: this.selectedWorldEventId }); } },
      { label: "REWARD SELECTED", run: () => { if (this.selectedWorldEventId) this.request("world_event_reward", { eventId: this.selectedWorldEventId }); } },
    ];
    if (this.category === "STRATEGY") return [
      ask("LOAD ARMIES", "list_armies"), ask("INVASIONS", "list_invasions", { territoryId: null }), ask("REALM WARS", "list_realm_wars"), ask("GUILD BATTLES", "list_guild_battles"),
      { label: "CREATE ARMY", run: () => { const name = this.prompt("Army name"); if (name) this.request("create_army", { name }); } },
      { label: "TRAIN SELECTED", run: () => { const unitType = this.prompt("Unit type"); const quantity = Number(this.prompt("Quantity")); if (this.selectedArmyId && unitType && Number.isSafeInteger(quantity)) this.request("train_army", { armyId: this.selectedArmyId, unitType, quantity }); } },
      { label: "REALM WAR", run: () => { const attackerRealmId = this.prompt("Attacker realm ID"); const defenderRealmId = this.prompt("Defender realm ID"); const targetTerritoryId = this.prompt("Target territory ID"); if (attackerRealmId && defenderRealmId && targetTerritoryId) this.request("create_realm_war", { attackerRealmId, defenderRealmId, targetTerritoryId }); } },
      { label: "GUILD BATTLE", run: () => { const attackerGuildId = this.prompt("Attacker guild ID"); const defenderGuildId = this.prompt("Defender guild ID"); const targetTerritoryId = this.prompt("Target territory ID"); if (attackerGuildId && defenderGuildId && targetTerritoryId) this.request("create_guild_battle", { attackerGuildId, defenderGuildId, targetTerritoryId }); } },
      { label: "GARRISON SELECTED", run: () => { const baseId = this.prompt("Base ID"); if (this.selectedArmyId && baseId) this.request("garrison_army", { armyId: this.selectedArmyId, baseId }); } },
      { label: "ASSIGN SELECTED", run: () => { const assignment = this.prompt("Assignment"); if (this.selectedArmyId && assignment) this.request("set_army_assignment", { armyId: this.selectedArmyId, assignment }); } },
      { label: "BATTLE SELECTED", run: () => { const defenderArmyId = this.prompt("Defender army ID (blank for none)"); const targetX = Number(this.prompt("Target X")); const targetY = Number(this.prompt("Target Y")); if (this.selectedArmyId && Number.isFinite(targetX) && Number.isFinite(targetY)) this.request("create_army_battle", { attackerArmyId: this.selectedArmyId, defenderArmyId: defenderArmyId || null, targetX, targetY }); } },
    ];
    if (this.category === "ENDGAME") return [
      ask("ENDGAME CREATURES", "list_endgame_creatures"), ask("MYTHIC CONTENT", "list_mythic_content"),
      { label: "ENGAGE SELECTED", run: () => { const payload = selectedCreatureEngagement(this.selectedEndgameCreatureId); if (payload) this.request("engage_endgame_creature", payload); } },
    ];
    return [];
  }

  private render(): void {
    this.title.setText("PLAYER • " + this.category);
    if (this.category === "INVENTORY") {
      const state = this.playerState();
      if (state) {
        const lines = Object.entries(state.inventory).filter(([, quantity]) => quantity > 0).map(([item, quantity]) => item + " × " + quantity);
        this.result.setText("GOLD " + state.gold + " • BADGES " + state.triumphBadges + "\n" + (lines.length ? lines.join("\n") : "Inventory empty"));
      } else {
        this.result.setText("Connect to the world to view inventory.");
      }
    }
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
    this.panel.setPosition(x, y).setSize(width, Math.min(560, Math.max(300, this.scene.scale.height - 90)));
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
