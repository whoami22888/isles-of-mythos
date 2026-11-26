// Prompt 036 Island Growth Fund. Intended for the test/CI database only.
// Do not apply this migration to production.
export const up = (pgm) => {
  pgm.sql("ALTER TABLE player_profiles ADD COLUMN IF NOT EXISTS pearls bigint NOT NULL DEFAULT 0");
  pgm.createTable("growth_fund_entitlements", {
    user_id: { type: "uuid", primaryKey: true, references: "users", onDelete: "CASCADE" },
    sku: { type: "text", notNull: true },
    purchased_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.createTable("growth_fund_claims", {
    user_id: { type: "uuid", notNull: true, references: "users", onDelete: "CASCADE" },
    milestone_level: { type: "integer", notNull: true },
    claimed_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.addConstraint("growth_fund_claims", "growth_fund_claims_pk", { primaryKey: ["user_id", "milestone_level"] });
};

export const down = (pgm) => {
  pgm.dropTable("growth_fund_claims");
  pgm.dropTable("growth_fund_entitlements");
};
