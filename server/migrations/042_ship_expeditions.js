// Ship expeditions (server-authoritative). A ship sails a fixed route for a server-timed
// duration; the reward is fixed per route and is credited exactly once on collect.
// While away the ship is 'docked' (an existing, previously unused player_ships status),
// so existing sail/naval code that requires 'active' already refuses it.
// Rollback: `down` first returns every ship on an uncollected expedition to 'active'
// (undoing the dock that `start` applied), then drops the table. No other table depends on it.
export const up = (pgm) => {
  pgm.createTable("ship_expeditions", {
    id: { type: "uuid", primaryKey: true, default: pgm.func("gen_random_uuid()") },
    owner_user_id: { type: "uuid", notNull: true, references: "users(id)", onDelete: "CASCADE" },
    ship_id: { type: "uuid", notNull: true, references: "player_ships(id)", onDelete: "CASCADE" },
    route_id: { type: "varchar(32)", notNull: true },
    request_id: { type: "varchar(64)", notNull: true },
    started_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
    returns_at: { type: "timestamptz", notNull: true },
    collected_at: { type: "timestamptz" },
    reward: { type: "jsonb", notNull: true },
  });
  pgm.addConstraint("ship_expeditions", "ship_expeditions_request_unique", { unique: ["owner_user_id", "request_id"] });
  pgm.addConstraint("ship_expeditions", "ship_expeditions_window_check", { check: "returns_at > started_at" });
  // At most one uncollected expedition per ship.
  pgm.createIndex("ship_expeditions", ["ship_id"], { name: "ship_expeditions_one_open_per_ship", unique: true, where: "collected_at IS NULL" });
  pgm.createIndex("ship_expeditions", ["owner_user_id", "started_at"]);
};

export const down = (pgm) => {
  pgm.sql(`UPDATE player_ships SET status='active', updated_at=CURRENT_TIMESTAMP
           WHERE status='docked' AND id IN (SELECT ship_id FROM ship_expeditions WHERE collected_at IS NULL)`);
  pgm.dropTable("ship_expeditions");
};
