// Daily objectives (server-authoritative). Progress is derived at read time from the
// existing gather/craft ledgers, so the latency-sensitive gather and craft paths gain
// no extra writes. Only the one-time reward claim is stored here.
// Rollback: `down` drops the claims table and the per-user gather index; no other
// table depends on either.
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
  pgm.createIndex("resource_gather_requests", ["user_id", "item_id", "created_at"], { name: "resource_gather_requests_user_item_created_idx" });
};

export const down = (pgm) => {
  pgm.dropIndex("resource_gather_requests", ["user_id", "item_id", "created_at"], { name: "resource_gather_requests_user_item_created_idx" });
  pgm.dropTable("daily_objective_claims");
};
