export const up = (pgm) => {
  pgm.createTable("shop_purchase_requests", {
    request_key: { type: "text", primaryKey: true },
    user_id: { type: "uuid", notNull: true, references: "users(id)", onDelete: "CASCADE" },
    fingerprint: { type: "text", notNull: true },
    response: { type: "jsonb", notNull: true },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.createIndex("shop_purchase_requests", "created_at");
};

export const down = (pgm) => {
  pgm.dropTable("shop_purchase_requests");
};
