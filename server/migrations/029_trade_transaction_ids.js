export const up = (pgm) => {
  pgm.addColumn("trade_requests", {
    transaction_id: { type: "text" },
  });
  pgm.sql("UPDATE trade_requests SET transaction_id = 'trade:' || request_key WHERE transaction_id IS NULL");
  pgm.alterColumn("trade_requests", "transaction_id", { notNull: true });
  pgm.createIndex("trade_requests", "transaction_id", { unique: true });
};

export const down = (pgm) => {
  pgm.dropIndex("trade_requests", "transaction_id");
  pgm.dropColumn("trade_requests", "transaction_id");
};
