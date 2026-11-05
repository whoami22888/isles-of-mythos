// Daily objectives (server-authoritative). Progress is derived at read time from the
// existing gather/craft ledgers, so the latency-sensitive gather and craft paths gain
// no extra writes. Only the one-time reward claim is stored here.
// No index is added to resource_gather_requests: an extra index there measurably
// raised gather tail latency in Performance Acceptance; progress reads use its
// (user_id, request_id) primary key prefix instead.
// Rollback: `down` drops the claims table; no other table depends on it.
export const up = (pgm) => {
  pgm.createTable("daily_objective_claims", {
    user_id: { type: "uuid", notNull: true, references: "player_profiles(user_id)", onDelete: "CASCADE" },
    objective_day: { type: "date", notNull: true },
    objective_id: { type: "varchar(64)", notNull: true },
    transaction_id: { type: "uuid", notNull: true, default: pgm.func("gen_random_uuid()") },
    reward_gold: { type: "bigint", notNull: true },
    claimed_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.addConstraint("daily_objective_claims", "daily_objective_claims_pk", { primaryKey: ["user_id", "objective_day", "objective_id"] });
  pgm.addConstraint("daily_objective_claims", "daily_objective_claims_transaction_id_unique", { unique: ["transaction_id"] });
  pgm.addConstraint("daily_objective_claims", "daily_objective_claims_reward_check", { check: "reward_gold > 0" });
};

export const down = (pgm) => {
  pgm.dropTable("daily_objective_claims");
};
