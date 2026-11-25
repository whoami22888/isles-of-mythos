// Separate Citadel 1–20 progression. Ordinary buildings stay on MAX_BUILDING_LEVEL=7.
// This does not alter protected migrations 029 or 036. Rollback: `down` drops the table.
export const up = (pgm) => {
  pgm.createTable("player_citadels", {
    base_id: { type: "uuid", notNull: true, references: "player_bases(id)", onDelete: "CASCADE" },
    owner_user_id: { type: "uuid", notNull: true, references: "users(id)", onDelete: "CASCADE" },
    citadel_level: { type: "integer", notNull: true, default: 1 },
    upgrade_started_at_unix: { type: "bigint", notNull: true, default: 0 },
    upgrade_completes_at_unix: { type: "bigint", notNull: true, default: 0 },
    upgrade_target_level: { type: "integer", notNull: true, default: 0 },
    guild_help_seconds_applied: { type: "integer", notNull: true, default: 0 },
    payment_path: { type: "varchar(16)" },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
    updated_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.addConstraint("player_citadels", "player_citadels_pk", { primaryKey: ["base_id"] });
  pgm.addConstraint("player_citadels", "player_citadels_owner_unique", { unique: ["owner_user_id"] });
  pgm.addConstraint("player_citadels", "player_citadels_level_check", {
    check: "citadel_level >= 1 AND citadel_level <= 20",
  });
  pgm.addConstraint("player_citadels", "player_citadels_target_check", {
    check: "upgrade_target_level >= 0 AND upgrade_target_level <= 20",
  });
  pgm.addConstraint("player_citadels", "player_citadels_help_check", {
    check: "guild_help_seconds_applied >= 0",
  });
  pgm.addConstraint("player_citadels", "player_citadels_times_check", {
    check: `(
      (upgrade_started_at_unix = 0 AND upgrade_completes_at_unix = 0 AND upgrade_target_level = 0 AND guild_help_seconds_applied = 0 AND payment_path IS NULL)
      OR (
        upgrade_started_at_unix > 0
        AND upgrade_completes_at_unix > upgrade_started_at_unix
        AND upgrade_target_level = citadel_level + 1
        AND payment_path IN ('resources', 'badges')
      )
    )`,
  });
  pgm.addConstraint("player_citadels", "player_citadels_payment_check", {
    check: "payment_path IS NULL OR payment_path IN ('resources', 'badges')",
  });
};

export const down = (pgm) => {
  pgm.dropTable("player_citadels");
};
