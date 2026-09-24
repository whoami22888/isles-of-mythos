export const up = (pgm) => {
  pgm.createTable("player_profiles", {
    user_id: { type: "uuid", primaryKey: true, references: "users(id)", onDelete: "CASCADE" },
    x: { type: "double precision", notNull: true, default: 0 },
    y: { type: "double precision", notNull: true, default: 0 },
    health: { type: "real", notNull: true, default: 100 },
    hunger: { type: "real", notNull: true, default: 100 },
    oxygen: { type: "real", notNull: true, default: 100 },
    xp: { type: "bigint", notNull: true, default: 0 },
    level: { type: "integer", notNull: true, default: 1 },
    gold: { type: "bigint", notNull: true, default: 0 },
    inventory: { type: "jsonb", notNull: true, default: pgm.func("'{}'::jsonb") },
    hotbar: { type: "jsonb", notNull: true, default: pgm.func("'[null,null,null,null,null,null,null,null]'::jsonb") },
    selected_hotbar_slot: { type: "smallint", notNull: true, default: 0 },
    updated_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.addConstraint("player_profiles", "player_profiles_health_range", { check: "health >= 0 AND health <= 100" });
  pgm.addConstraint("player_profiles", "player_profiles_hunger_range", { check: "hunger >= 0 AND hunger <= 100" });
  pgm.addConstraint("player_profiles", "player_profiles_oxygen_range", { check: "oxygen >= 0 AND oxygen <= 100" });
  pgm.addConstraint("player_profiles", "player_profiles_level_positive", { check: "level >= 1" });
  pgm.addConstraint("player_profiles", "player_profiles_hotbar_slot_range", { check: "selected_hotbar_slot >= 0 AND selected_hotbar_slot < 8" });
};
export const down = (pgm) => { pgm.dropTable("player_profiles"); };
