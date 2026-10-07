export const up = (pgm) => {
  pgm.addColumn("shop_purchase_requests", {
    transaction_id: { type: "uuid", default: pgm.func("gen_random_uuid()") },
  });
  pgm.sql("UPDATE shop_purchase_requests SET transaction_id=gen_random_uuid() WHERE transaction_id IS NULL");
  pgm.alterColumn("shop_purchase_requests", "transaction_id", { notNull: true });
  pgm.addConstraint("shop_purchase_requests", "shop_purchase_requests_transaction_id_unique", { unique: ["transaction_id"] });
};

export const down = (pgm) => {
  pgm.dropConstraint("shop_purchase_requests", "shop_purchase_requests_transaction_id_unique");
  pgm.dropColumn("shop_purchase_requests", "transaction_id");
};
