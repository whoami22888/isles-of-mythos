export const up = (pgm) => {
  pgm.addColumn("guild_bank_transactions", {
    transaction_id: { type: "uuid", default: pgm.func("gen_random_uuid()") },
  });
  pgm.sql("UPDATE guild_bank_transactions SET transaction_id=gen_random_uuid() WHERE transaction_id IS NULL");
  pgm.alterColumn("guild_bank_transactions", "transaction_id", { notNull: true });
  pgm.addConstraint("guild_bank_transactions", "guild_bank_transactions_transaction_id_unique", { unique: ["transaction_id"] });
};

export const down = (pgm) => {
  pgm.dropConstraint("guild_bank_transactions", "guild_bank_transactions_transaction_id_unique");
  pgm.dropColumn("guild_bank_transactions", "transaction_id");
};
