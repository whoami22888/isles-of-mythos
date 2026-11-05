// Weekly guild objectives (server-authoritative). Progress is summed at read time from
// the existing resource_gather_requests ledger for the guild's current members (only
// gathers made since each member joined, within the current UTC ISO week). Only the
// once-per-player-per-week reward claim is stored. Rollback: `down` drops the table.
export const up = (pgm) => {
  pgm.createTable("guild_objective_claims", {
    user_id: { type: "uuid", notNull: true, references: "users(id)", onDelete: "CASCADE" },
    week_start: { type: "date", notNull: true },
    objective_id: { type: "varchar(64)", notNull: true },
    guild_id: { type: "uuid", notNull: true, references: "guilds(id)", onDelete: "CASCADE" },
    transaction_id: { type: "uuid", notNull: true, default: pgm.func("gen_random_uuid()") },
    reward_gold: { type: "bigint", notNull: true },
    claimed_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  // Keyed by player, not guild: hopping guilds cannot claim the same week twice.
  pgm.addConstraint("guild_objective_claims", "guild_objective_claims_pk", { primaryKey: ["user_id", "week_start", "objective_id"] });
  pgm.addConstraint("guild_objective_claims", "guild_objective_claims_transaction_id_unique", { unique: ["transaction_id"] });
  pgm.addConstraint("guild_objective_claims", "guild_objective_claims_reward_check", { check: "reward_gold > 0" });
};

export const down = (pgm) => {
  pgm.dropTable("guild_objective_claims");
};
