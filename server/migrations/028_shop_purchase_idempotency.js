export const up = (pgm) => {
  pgm.createTable("shop_purchase_requests", {
    request_key: { type: "varchar(128)", primaryKey: true },
    user_id: { type: "uuid", notNull: true, references: "player_profiles(user_id)", onDelete: "CASCADE" },
    fingerprint: { type: "varchar(512)", notNull: true },
    response: { type: "jsonb", notNull: true },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.createIndex("shop_purchase_requests", ["user_id", "created_at"]);
};

export const down = (pgm) => {
  pgm.dropTable("shop_purchase_requests");
};
