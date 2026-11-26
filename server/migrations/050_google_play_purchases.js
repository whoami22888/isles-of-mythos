// Prompt 035 Google Play purchase receipts. Intended for the test/CI database only.
// Do not apply this migration to production.
export const up = (pgm) => {
  pgm.createTable("google_play_purchases", {
    purchase_token: { type: "text", primaryKey: true },
    user_id: { type: "uuid", notNull: true, references: "users", onDelete: "CASCADE" },
    product_id: { type: "text", notNull: true },
    pearls_credited: { type: "bigint", notNull: true },
    fulfilled_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.sql("ALTER TABLE player_profiles ADD COLUMN IF NOT EXISTS pearls bigint NOT NULL DEFAULT 0");
};

export const down = (pgm) => {
  pgm.sql("ALTER TABLE player_profiles DROP COLUMN IF EXISTS pearls");
  pgm.dropTable("google_play_purchases");
};
