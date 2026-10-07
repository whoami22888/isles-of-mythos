export const up = (pgm) => {
  pgm.createTable("guild_bank_requests", {
    request_key: { type: "varchar(128)", primaryKey: true },
    user_id: { type: "uuid", notNull: true, references: "player_profiles(user_id)", onDelete: "CASCADE" },
    fingerprint: { type: "text", notNull: true },
    transaction_id: { type: "uuid", notNull: true, default: pgm.func("gen_random_uuid()") },
    response: { type: "jsonb", notNull: true },
    created_at: { type: "timestamp with time zone", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.addConstraint("guild_bank_requests", "guild_bank_requests_transaction_id_unique", { unique: ["transaction_id"] });
  pgm.createIndex("guild_bank_requests", ["user_id", "created_at"]);

  pgm.createTable("ship_cargo_requests", {
    request_key: { type: "varchar(128)", primaryKey: true },
    user_id: { type: "uuid", notNull: true, references: "player_profiles(user_id)", onDelete: "CASCADE" },
    fingerprint: { type: "text", notNull: true },
    transaction_id: { type: "uuid", notNull: true, default: pgm.func("gen_random_uuid()") },
    response: { type: "jsonb", notNull: true },
    created_at: { type: "timestamp with time zone", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.addConstraint("ship_cargo_requests", "ship_cargo_requests_transaction_id_unique", { unique: ["transaction_id"] });
  pgm.createIndex("ship_cargo_requests", ["user_id", "created_at"]);

  pgm.createTable("base_storage_requests", {
    request_key: { type: "varchar(128)", primaryKey: true },
    user_id: { type: "uuid", notNull: true, references: "player_profiles(user_id)", onDelete: "CASCADE" },
    fingerprint: { type: "text", notNull: true },
    transaction_id: { type: "uuid", notNull: true, default: pgm.func("gen_random_uuid()") },
    response: { type: "jsonb", notNull: true },
    created_at: { type: "timestamp with time zone", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.addConstraint("base_storage_requests", "base_storage_requests_transaction_id_unique", { unique: ["transaction_id"] });
  pgm.createIndex("base_storage_requests", ["user_id", "created_at"]);
};

export const down = (pgm) => {
  pgm.dropTable("base_storage_requests");
  pgm.dropTable("ship_cargo_requests");
  pgm.dropTable("guild_bank_requests");
};
