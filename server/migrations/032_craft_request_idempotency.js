export const up = (pgm) => {
  pgm.createTable("craft_requests", {
    request_key: { type: "varchar(128)", primaryKey: true },
    user_id: { type: "uuid", notNull: true, references: "player_profiles(user_id)", onDelete: "CASCADE" },
    fingerprint: { type: "varchar(512)", notNull: true },
    transaction_id: { type: "uuid", notNull: true, default: pgm.func("gen_random_uuid()") },
    response: { type: "jsonb", notNull: true },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.addConstraint("craft_requests", "craft_requests_transaction_id_unique", { unique: ["transaction_id"] });
  pgm.createIndex("craft_requests", ["user_id", "created_at"]);
};

export const down = (pgm) => {
  pgm.dropTable("craft_requests");
};
