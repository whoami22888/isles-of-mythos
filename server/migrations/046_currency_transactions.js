// Ledger for Prompt 023 atomic Gold Doubloon purchases. Does not touch 029/036.
export const up = (pgm) => {
  pgm.createTable("currency_transactions", {
    id: { type: "uuid", primaryKey: true, default: pgm.func("gen_random_uuid()") },
    user_id: { type: "uuid", notNull: true, references: "player_profiles(user_id)", onDelete: "CASCADE" },
    item_id: { type: "varchar(64)", notNull: true },
    quantity: { type: "integer", notNull: true },
    gold_spent: { type: "bigint", notNull: true },
    gold_before: { type: "bigint", notNull: true },
    gold_after: { type: "bigint", notNull: true },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.addConstraint("currency_transactions", "currency_transactions_quantity_positive", {
    check: "quantity > 0",
  });
  pgm.addConstraint("currency_transactions", "currency_transactions_gold_spent_nonnegative", {
    check: "gold_spent >= 0",
  });
  pgm.createIndex("currency_transactions", ["user_id", "created_at"]);
};

export const down = (pgm) => {
  pgm.dropTable("currency_transactions");
};
