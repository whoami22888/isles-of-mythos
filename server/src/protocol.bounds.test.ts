import { describe, expect, it } from "vitest";
import { parseClientMessage } from "./protocol.js";

const parse = (message: Record<string, unknown>) => parseClientMessage(JSON.stringify(message));
const MAX_GOLD = "9223372036854775807";
const OVER_GOLD = "9223372036854775808";
const long = (n: number) => "x".repeat(n);

function nested(depth: number): Record<string, unknown> {
  let node: Record<string, unknown> = { leaf: 1 };
  for (let i = 0; i < depth; i += 1) node = { child: node };
  return node;
}

describe("NET-04 gap 1: bounded jsonb payloads", () => {
  const formation = (layout: unknown) => ({ type: "set_army_formation", requestId: "r1", armyId: "a1", name: "line", formationType: "line", layout });
  const order = (payload: unknown) => ({ type: "issue_army_order", requestId: "r1", armyId: "a1", battleId: null, orderType: "move", targetUnitId: null, targetX: 1, targetY: 2, payload });

  it("accepts small layouts and payloads", () => {
    expect(parse(formation({ rows: [[1, 2], [3, 4]], slot: "front" }))).not.toBeNull();
    expect(parse(order({ stance: "hold", priority: 2 }))).not.toBeNull();
    expect(parse(formation({}))).not.toBeNull();
    expect(parse(order({}))).not.toBeNull();
  });

  it("rejects payloads whose serialized size exceeds the cap", () => {
    expect(parse(formation({ blob: long(8000) }))).toBeNull();
    expect(parse(order({ blob: long(8000) }))).toBeNull();
  });

  it("measures the size cap in UTF-8 bytes, not UTF-16 code units", () => {
    const layout: Record<string, string> = {};
    for (let i = 0; i < 12; i += 1) layout[`k${i}`] = "\u00e9".repeat(200);
    const json = JSON.stringify(layout);
    expect(json.length).toBeLessThan(4096);
    expect(Buffer.byteLength(json, "utf8")).toBeGreaterThan(4096);
    expect(parse(formation(layout))).toBeNull();
    expect(parse(order(layout))).toBeNull();
  });

  it("accepts a payload at exactly 4096 UTF-8 bytes and rejects 4097", () => {
    const withTail = (n: number) => {
      const layout: Record<string, string> = {};
      for (let i = 0; i < 15; i += 1) layout[`k${i}`] = "x".repeat(250);
      layout.tail = "x".repeat(n);
      return layout;
    };
    const base = Buffer.byteLength(JSON.stringify(withTail(0)), "utf8");
    const fill = 4096 - base;
    expect(fill).toBeGreaterThan(0);
    expect(fill).toBeLessThanOrEqual(256);
    expect(Buffer.byteLength(JSON.stringify(withTail(fill)), "utf8")).toBe(4096);
    expect(parse(formation(withTail(fill)))).not.toBeNull();
    expect(parse(order(withTail(fill)))).not.toBeNull();
    expect(Buffer.byteLength(JSON.stringify(withTail(fill + 1)), "utf8")).toBe(4097);
    expect(parse(formation(withTail(fill + 1)))).toBeNull();
    expect(parse(order(withTail(fill + 1)))).toBeNull();
  });

  it("rejects deeply nested payloads", () => {
    expect(parse(formation(nested(20)))).toBeNull();
    expect(parse(order(nested(20)))).toBeNull();
  });

  it("rejects payloads with too many keys or array items", () => {
    const manyKeys: Record<string, number> = {};
    for (let i = 0; i < 200; i += 1) manyKeys[`k${i}`] = i;
    expect(parse(formation(manyKeys))).toBeNull();
    expect(parse(order({ list: Array.from({ length: 500 }, (_, i) => i) }))).toBeNull();
  });

  it("rejects __proto__, constructor and prototype keys", () => {
    expect(parseClientMessage('{"type":"set_army_formation","requestId":"r1","armyId":"a1","name":"n","formationType":"line","layout":{"__proto__":{"x":1}}}')).toBeNull();
    expect(parseClientMessage('{"type":"issue_army_order","requestId":"r1","armyId":"a1","battleId":null,"orderType":"move","targetUnitId":null,"targetX":1,"targetY":2,"payload":{"constructor":{"x":1}}}')).toBeNull();
  });

  it("bounds the string fields next to the payload", () => {
    expect(parse({ ...formation({}), name: long(65) })).toBeNull();
    expect(parse({ ...formation({}), name: "" })).toBeNull();
    expect(parse({ ...formation({}), formationType: long(33) })).toBeNull();
    expect(parse({ ...order({}), orderType: long(33) })).toBeNull();
    expect(parse({ ...order({}), orderType: "" })).toBeNull();
  });
});

describe("NET-04 gap 2: gold and price strings", () => {
  const trade = (gold: unknown) => ({ type: "trade", requestId: "r1", toUserId: "u2", gold, items: [] });
  const bad = ["", "-1", "1.5", "1e3", " 12", "12 ", "0x10", "01", "+5", "abc", OVER_GOLD, "1".repeat(32)];

  it("accepts canonical non-negative integer strings up to the 64-bit maximum", () => {
    for (const gold of ["0", "1", "250", MAX_GOLD]) {
      expect(parse(trade(gold))).not.toBeNull();
      expect(parse({ type: "guild_bank_deposit", requestId: "r1", guildId: "g1", itemId: "i1", quantity: 1, gold })).not.toBeNull();
      expect(parse({ type: "guild_bank_withdraw", requestId: "r1", guildId: "g1", itemId: "i1", quantity: 1, gold })).not.toBeNull();
    }
  });

  it("rejects malformed or overflowing gold strings in trade and guild bank", () => {
    for (const gold of bad) {
      expect(parse(trade(gold)), `trade ${gold}`).toBeNull();
      expect(parse({ type: "guild_bank_deposit", requestId: "r1", guildId: "g1", itemId: "i1", quantity: 1, gold }), `deposit ${gold}`).toBeNull();
      expect(parse({ type: "guild_bank_withdraw", requestId: "r1", guildId: "g1", itemId: "i1", quantity: 1, gold }), `withdraw ${gold}`).toBeNull();
    }
    expect(parse(trade(5))).toBeNull();
  });

  it("rejects a guild bank transfer that moves nothing", () => {
    expect(parse({ type: "guild_bank_deposit", requestId: "r1", guildId: "g1", itemId: "i1", quantity: 0, gold: "0" })).toBeNull();
    expect(parse({ type: "guild_bank_withdraw", requestId: "r1", guildId: "g1", itemId: "i1", quantity: 0, gold: "0" })).toBeNull();
    expect(parse({ type: "guild_bank_deposit", requestId: "r1", guildId: "g1", itemId: "i1", quantity: 0, gold: "100" })).not.toBeNull();
    // Gold-only treasury operations use an empty itemId (stored as NULL); must stay valid.
    for (const type of ["guild_bank_deposit", "guild_bank_withdraw"] as const) {
      expect(parse({ type, requestId: "r1", guildId: "g1", itemId: "", quantity: 0, gold: "100" }), `${type} gold-only`).not.toBeNull();
      expect(parse({ type, requestId: "r1", guildId: "g1", itemId: "", quantity: 1, gold: "100" }), `${type} empty id with item`).toBeNull();
      expect(parse({ type, requestId: "r1", guildId: "g1", itemId: "x".repeat(129), quantity: 0, gold: "100" }), `${type} oversize id`).toBeNull();
    }
  });

  it("rejects malformed auction prices", () => {
    for (const price of bad) {
      expect(parse({ type: "auction_create", requestId: "r1", itemId: "i1", quantity: 1, startPrice: price, buyNowPrice: null, durationMs: 60000 }), `start ${price}`).toBeNull();
      expect(parse({ type: "auction_create", requestId: "r1", itemId: "i1", quantity: 1, startPrice: "10", buyNowPrice: price, durationMs: 60000 }), `buyNow ${price}`).toBeNull();
      expect(parse({ type: "auction_bid", requestId: "r1", listingId: "l1", amount: price }), `bid ${price}`).toBeNull();
      expect(parse({ type: "auction_list", requestId: "r1", itemId: null, minPrice: price, maxPrice: null }), `min ${price}`).toBeNull();
      expect(parse({ type: "auction_list", requestId: "r1", itemId: null, minPrice: null, maxPrice: price }), `max ${price}`).toBeNull();
    }
  });

  it("accepts well-formed auction prices", () => {
    expect(parse({ type: "auction_create", requestId: "r1", itemId: "i1", quantity: 1, startPrice: "10", buyNowPrice: "100", durationMs: 60000 })).not.toBeNull();
    expect(parse({ type: "auction_bid", requestId: "r1", listingId: "l1", amount: "11" })).toEqual({ type: "auction_bid", requestId: "r1", listingId: "l1", amount: "11" });
    expect(parse({ type: "auction_list", requestId: "r1", itemId: null, minPrice: "1", maxPrice: MAX_GOLD })).not.toBeNull();
  });

  it("bounds create_trade_route.quantity", () => {
    const route = (quantity: unknown) => ({ type: "create_trade_route", requestId: "r1", sourceTerritoryId: "t1", destinationTerritoryId: "t2", resourceKey: "wood", quantity, travelSeconds: 60, guildId: null, realmId: null });
    expect(parse(route("500"))).not.toBeNull();
    expect(parse(route("9".repeat(200)))).toBeNull();
    expect(parse(route(OVER_GOLD))).toBeNull();
    expect(parse(route("0"))).toBeNull();
    expect(parse(route("-5"))).toBeNull();
    expect(parse({ ...route("5"), sourceTerritoryId: long(65) })).toBeNull();
    expect(parse({ ...route("5"), sourceTerritoryId: "" })).toBeNull();
    expect(parse({ ...route("5"), resourceKey: long(65) })).toBeNull();
    expect(parse({ ...route("5"), resourceKey: "" })).toBeNull();
  });
});

describe("NET-04 gap 3: unbounded or empty id strings", () => {
  const tooLong = long(129);
  const cases: Array<[string, Record<string, unknown>, string]> = [
    ["invite_guild_member", { type: "invite_guild_member", requestId: "r1", guildId: "g1", targetUserId: "u1" }, "guildId"],
    ["invite_guild_member", { type: "invite_guild_member", requestId: "r1", guildId: "g1", targetUserId: "u1" }, "targetUserId"],
    ["accept_guild_invite", { type: "accept_guild_invite", requestId: "r1", invitationId: "i1" }, "invitationId"],
    ["decline_guild_invite", { type: "decline_guild_invite", requestId: "r1", invitationId: "i1" }, "invitationId"],
    ["leave_guild", { type: "leave_guild", requestId: "r1", guildId: "g1" }, "guildId"],
    ["remove_guild_member", { type: "remove_guild_member", requestId: "r1", guildId: "g1", targetUserId: "u1" }, "targetUserId"],
    ["set_guild_rank", { type: "set_guild_rank", requestId: "r1", guildId: "g1", targetUserId: "u1", rank: "officer" }, "guildId"],
    ["set_guild_permission", { type: "set_guild_permission", requestId: "r1", guildId: "g1", rank: "officer", permission: "bank_withdraw", enabled: true }, "guildId"],
    ["set_guild_permission", { type: "set_guild_permission", requestId: "r1", guildId: "g1", rank: "officer", permission: "bank_withdraw", enabled: true }, "permission"],
    ["set_guild_permission", { type: "set_guild_permission", requestId: "r1", guildId: "g1", rank: "officer", permission: "bank_withdraw", enabled: true }, "rank"],
    ["guild_bank", { type: "guild_bank", requestId: "r1", guildId: "g1" }, "guildId"],
    ["guild_bank_deposit", { type: "guild_bank_deposit", requestId: "r1", guildId: "g1", itemId: "i1", quantity: 1, gold: "0" }, "itemId"],
    ["build_guild_infrastructure", { type: "build_guild_infrastructure", requestId: "r1", guildId: "g1", structureType: "guild_hall" }, "guildId"],
    ["train_army", { type: "train_army", requestId: "r1", armyId: "a1", unitType: "pirate", quantity: 1 }, "armyId"],
    ["train_army", { type: "train_army", requestId: "r1", armyId: "a1", unitType: "pirate", quantity: 1 }, "unitType"],
    ["garrison_army", { type: "garrison_army", requestId: "r1", armyId: "a1", baseId: "b1" }, "baseId"],
    ["add_army_creature", { type: "add_army_creature", requestId: "r1", armyId: "a1", creatureId: "c1" }, "creatureId"],
    ["set_army_assignment", { type: "set_army_assignment", requestId: "r1", armyId: "a1", assignment: "patrol" }, "assignment"],
    ["nominate_commander", { type: "nominate_commander", requestId: "r1", guildId: "g1", targetUserId: "u1" }, "guildId"],
    ["assign_army_commander", { type: "assign_army_commander", requestId: "r1", armyId: "a1", commanderUserId: "u1" }, "commanderUserId"],
    ["deploy_battle_unit", { type: "deploy_battle_unit", requestId: "r1", battleId: "b1", unitId: "u1", formationSlot: 1 }, "unitId"],
    ["army_tactical_action", { type: "army_tactical_action", requestId: "r1", battleId: "b1", unitId: "u1", actionType: "retreat", targetUnitId: null }, "unitId"],
    ["build_defense", { type: "build_defense", requestId: "r1", baseId: "b1", structureType: "cannon_tower", gridX: 1, gridY: 1 }, "structureType"],
    ["assign_ship_crew", { type: "assign_ship_crew", requestId: "r1", shipId: "s1", creatureId: "c1", role: "gunner", skill: 10, morale: 50 }, "shipId"],
    ["assign_ship_crew", { type: "assign_ship_crew", requestId: "r1", shipId: "s1", creatureId: "c1", role: "gunner", skill: 10, morale: 50 }, "creatureId"],
    ["fire_cannon", { type: "fire_cannon", requestId: "r1", shipId: "s1", targetShipId: "s2" }, "shipId"],
    ["fire_cannon", { type: "fire_cannon", requestId: "r1", shipId: "s1", targetShipId: "s2" }, "targetShipId"],
    ["board_ship", { type: "board_ship", requestId: "r1", shipId: "s1", targetShipId: "s2" }, "targetShipId"],
    ["assign_ship_npc_crew", { type: "assign_ship_npc_crew", requestId: "r1", shipId: "s1", npcType: "pirate", role: "gunner", skill: 10, morale: 50 }, "shipId"],
    ["auction_create", { type: "auction_create", requestId: "r1", itemId: "i1", quantity: 1, startPrice: "10", buyNowPrice: null, durationMs: 60000 }, "itemId"],
    ["auction_list", { type: "auction_list", requestId: "r1", itemId: "i1", minPrice: null, maxPrice: null }, "itemId"],
    ["chat_send", { type: "chat_send", requestId: "r1", channel: "whisper", body: "hi", recipientUserId: "u1", guildId: null, partyId: null }, "recipientUserId"],
    ["chat_history", { type: "chat_history", requestId: "r1", channel: "guild", recipientUserId: null, guildId: "g1", partyId: null }, "guildId"],
    ["chat_send", { type: "chat_send", requestId: "r1", channel: "party", body: "hi", recipientUserId: null, guildId: null, partyId: "p1" }, "partyId"],
    ["list_invasions", { type: "list_invasions", requestId: "r1", territoryId: "t1" }, "territoryId"],
    ["world_event_contribute", { type: "world_event_contribute", requestId: "r1", eventId: "e1" }, "eventId"],
  ];

  for (const [name, base, field] of cases) {
    it(`${name}: rejects oversized ${field}`, () => {
      expect(parse(base), "baseline must be valid").not.toBeNull();
      expect(parse({ ...base, [field]: tooLong })).toBeNull();
    });
  }

  const emptyRejected: Array<[string, Record<string, unknown>, string]> = cases.filter(([name, , field]) => !(name === "chat_send" && field === "recipientUserId") && !(name === "chat_history" && field === "guildId"));
  for (const [name, base, field] of emptyRejected) {
    it(`${name}: rejects empty ${field}`, () => {
      expect(parse({ ...base, [field]: "" })).toBeNull();
    });
  }

  it("rejects empty optional ids that are not null", () => {
    expect(parse({ type: "chat_send", requestId: "r1", channel: "whisper", body: "hi", recipientUserId: "", guildId: null, partyId: null })).toBeNull();
    expect(parse({ type: "chat_history", requestId: "r1", channel: "guild", recipientUserId: null, guildId: "", partyId: null })).toBeNull();
    expect(parse({ type: "issue_army_order", requestId: "r1", armyId: "a1", battleId: "", orderType: "move", targetUnitId: null, targetX: 1, targetY: 2, payload: {} })).toBeNull();
    expect(parse({ type: "issue_army_order", requestId: "r1", armyId: "a1", battleId: null, orderType: "move", targetUnitId: "", targetX: 1, targetY: 2, payload: {} })).toBeNull();
  });

  it("rejects over-long ids in the social and auction id-only messages", () => {
    expect(parse({ type: "add_friend", requestId: "r1", targetUserId: tooLong })).toBeNull();
    expect(parse({ type: "auction_buy_now", requestId: "r1", listingId: tooLong })).toBeNull();
  });

  it("rejects non-string and over-long world event request ids", () => {
    expect(parse({ type: "list_world_events", requestId: 5 })).toBeNull();
    expect(parse({ type: "list_world_events", requestId: long(65) })).toBeNull();
    expect(parse({ type: "list_world_events", requestId: "" })).toBeNull();
    expect(parse({ type: "world_event_contribute", requestId: long(65), eventId: "e1" })).toBeNull();
  });

  it("bounds names and tags", () => {
    expect(parse({ type: "create_guild", requestId: "r1", name: "", tag: "TAG" })).toBeNull();
    expect(parse({ type: "create_guild", requestId: "r1", name: "Crew", tag: "" })).toBeNull();
    expect(parse({ type: "create_army", requestId: "r1", name: "" })).toBeNull();
    expect(parse({ type: "create_ship", requestId: "r1", name: "", shipClass: "sloop" })).toBeNull();
    expect(parse({ type: "create_base", requestId: "r1", name: "", x: 0, y: 0 })).toBeNull();
  });
});

describe("NET-04 gap 4: unbounded numerics", () => {
  it("bounds territory_at coordinates", () => {
    expect(parse({ type: "territory_at", requestId: "r1", x: 10, y: -10 })).not.toBeNull();
    expect(parse({ type: "territory_at", requestId: "r1", x: 1_000_001, y: 0 })).toBeNull();
    expect(parse({ type: "territory_at", requestId: "r1", x: 0, y: -1_000_001 })).toBeNull();
    expect(parse({ type: "territory_at", requestId: "r1", x: Number.MAX_SAFE_INTEGER, y: 0 })).toBeNull();
  });

  it("bounds build_defense grid coordinates", () => {
    const base = { type: "build_defense", requestId: "r1", baseId: "b1", structureType: "cannon_tower" };
    expect(parse({ ...base, gridX: 128, gridY: -128 })).not.toBeNull();
    expect(parse({ ...base, gridX: 129, gridY: 0 })).toBeNull();
    expect(parse({ ...base, gridX: 0, gridY: -129 })).toBeNull();
  });

  it("bounds create_army_battle target coordinates", () => {
    const base = { type: "create_army_battle", requestId: "r1", attackerArmyId: "a1", defenderArmyId: null };
    expect(parse({ ...base, targetX: 500, targetY: -500 })).not.toBeNull();
    expect(parse({ ...base, targetX: 1e12, targetY: 0 })).toBeNull();
    expect(parse({ ...base, targetX: 0, targetY: -1e12 })).toBeNull();
  });

  it("bounds issue_army_order target coordinates", () => {
    const base = { type: "issue_army_order", requestId: "r1", armyId: "a1", battleId: null, orderType: "move", targetUnitId: null, payload: {} };
    expect(parse({ ...base, targetX: 500, targetY: -500 })).not.toBeNull();
    expect(parse({ ...base, targetX: null, targetY: null })).not.toBeNull();
    expect(parse({ ...base, targetX: 1e12, targetY: 0 })).toBeNull();
    expect(parse({ ...base, targetX: 0, targetY: -1e12 })).toBeNull();
  });

  it("bounds build.level", () => {
    const base = { type: "build", requestId: "r1", buildingType: "storage", gridX: 1, gridY: 1 };
    expect(parse({ ...base, level: 1 })).not.toBeNull();
    expect(parse({ ...base, level: 7 })).not.toBeNull();
    expect(parse({ ...base, level: 0 })).toBeNull();
    expect(parse({ ...base, level: -1 })).toBeNull();
    expect(parse({ ...base, level: 8 })).toBeNull();
    expect(parse({ ...base, level: Number.MAX_SAFE_INTEGER })).toBeNull();
  });

  it("bounds auction level filters", () => {
    const base = { type: "auction_list", requestId: "r1", itemId: null, minPrice: null, maxPrice: null };
    expect(parse({ ...base, minLevel: 1, maxLevel: 50 })).not.toBeNull();
    expect(parse({ ...base, minLevel: 100, maxLevel: 100 })).not.toBeNull();
    expect(parse({ ...base, minLevel: 0 })).toBeNull();
    expect(parse({ ...base, maxLevel: 0 })).toBeNull();
    expect(parse({ ...base, maxLevel: 101 })).toBeNull();
    expect(parse({ ...base, minLevel: -1 })).toBeNull();
    expect(parse({ ...base, maxLevel: Number.MAX_SAFE_INTEGER })).toBeNull();
    expect(parse({ ...base, minLevel: 10, maxLevel: 5 })).toBeNull();
  });

  it("bounds create_trade_route travelSeconds as before and the world event request id", () => {
    const route = { type: "create_trade_route", requestId: "r1", sourceTerritoryId: "t1", destinationTerritoryId: "t2", resourceKey: "wood", quantity: "5", guildId: null, realmId: null };
    expect(parse({ ...route, travelSeconds: 604800 })).not.toBeNull();
    expect(parse({ ...route, travelSeconds: 604801 })).toBeNull();
  });

  it("keeps previously valid messages valid", () => {
    expect(parse({ type: "train_army", requestId: "r1", armyId: "a1", unitType: "pirate", quantity: 1000 })).not.toBeNull();
    expect(parse({ type: "train_army", requestId: "r1", armyId: "a1", unitType: "pirate", quantity: 1001 })).toBeNull();
    expect(parse({ type: "sail", requestId: "r1", shipId: "s1", dx: 1, dy: 0, dt: 1 })).not.toBeNull();
  });
});

describe("id-only social/auction messages are rebuilt, not spread (NET-04 slice 2a)", () => {
  const cases: Array<[string, string]> = [
    ["add_friend", "targetUserId"], ["remove_friend", "targetUserId"], ["block_user", "targetUserId"],
    ["unblock_user", "targetUserId"], ["party_invite", "targetUserId"], ["party_kick", "targetUserId"],
    ["party_accept", "invitationId"], ["auction_buy_now", "listingId"], ["auction_cancel", "listingId"],
  ];
  it.each(cases)("%s drops every field except type, requestId and %s", (type, key) => {
    const parsed = parse({ type, requestId: "r1", [key]: "abc", userId: "attacker", isAdmin: true, extra: { deep: 1 }, gold: "999" });
    expect(parsed).toEqual({ type, requestId: "r1", [key]: "abc" });
    expect(Object.keys(parsed as object).sort()).toEqual(["requestId", key, "type"].sort());
  });
  it("does not carry an own __proto__ key through", () => {
    const raw = '{"type":"add_friend","requestId":"r1","targetUserId":"abc","__proto__":{"polluted":true}}';
    const parsed = parseClientMessage(raw) as Record<string, unknown> | null;
    expect(parsed).toEqual({ type: "add_friend", requestId: "r1", targetUserId: "abc" });
    expect(Object.getPrototypeOf(parsed)).toBe(Object.prototype);
    expect(({} as Record<string, unknown>).polluted).toBeUndefined();
  });
});

describe("server-only operations are not client messages (NET-04 slice 2b)", () => {
  it("tick_realm_ai is rejected by the parser; realm AI is server-scheduled", () => {
    expect(parse({ type: "tick_realm_ai", requestId: "r1" })).toBeNull();
  });
  it("change_realm_reputation is rejected: clients cannot grant themselves reputation", () => {
    expect(parse({ type: "change_realm_reputation", requestId: "r1", realm: "storm_empire", delta: 5 })).toBeNull();
  });
  it("start_breeding never carries a client-chosen duration (server default only)", () => {
    const base = { type: "start_breeding", requestId: "r1", baseId: "b", penBuildingId: "p", parentAId: "a", parentBId: "c" };
    expect(parse(base)).toEqual(base);
    expect(parse({ ...base, durationMs: 1 })).toEqual(base);
    expect(parse({ ...base, durationMs: 86_400_000 })).toEqual(base);
  });
});


