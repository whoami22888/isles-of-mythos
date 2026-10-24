/** Additive IOM-04 research/training data. Does not alter protected historical migrations. */
export const up = (pgm) => {
  pgm.createTable("player_creature_skills", {
    user_id: { type: "uuid", notNull: true, references: "player_profiles(user_id)", onDelete: "CASCADE" },
    skill_id: { type: "varchar(32)", notNull: true },
    experience: { type: "integer", notNull: true, default: 0 },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
    updated_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.addConstraint("player_creature_skills", "player_creature_skills_pk", { primaryKey: ["user_id", "skill_id"] });
  pgm.addConstraint("player_creature_skills", "player_creature_skills_xp_range", { check: "experience >= 0 AND experience <= 900" });
  pgm.createTable("creature_training_progress", {
    creature_id: { type: "uuid", primaryKey: true, references: "player_creatures(id)", onDelete: "CASCADE" },
    experience: { type: "integer", notNull: true, default: 0 },
    bond: { type: "integer", notNull: true, default: 40 },
    learned_commands: { type: "jsonb", notNull: true, default: pgm.func("'[]'::jsonb") },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
    updated_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.addConstraint("creature_training_progress", "creature_training_xp_range", { check: "experience >= 0 AND experience <= 900" });
  pgm.addConstraint("creature_training_progress", "creature_training_bond_range", { check: "bond >= 0 AND bond <= 100" });
  pgm.addConstraint("creature_training_progress", "creature_training_commands_array", { check: "jsonb_typeof(learned_commands) = 'array'" });
  pgm.createTable("creature_progression_requests", {
    request_key: { type: "varchar(128)", primaryKey: true },
    user_id: { type: "uuid", notNull: true, references: "player_profiles(user_id)", onDelete: "CASCADE" },
    fingerprint: { type: "varchar(256)", notNull: true },
    response: { type: "jsonb", notNull: true },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.createIndex("creature_progression_requests", ["user_id", "created_at"]);
};
export const down = (pgm) => {
  pgm.dropTable("creature_progression_requests");
  pgm.dropTable("creature_training_progress");
  pgm.dropTable("player_creature_skills");
};
