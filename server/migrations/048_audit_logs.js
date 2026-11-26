// Prompt 025 security-flag audit trail for Citadel soft-wall rejects. Does not touch 029/036.
export const up = (pgm) => {
  pgm.createTable("audit_logs", {
    id: { type: "uuid", primaryKey: true, default: pgm.func("gen_random_uuid()") },
    user_id: { type: "uuid", references: "player_profiles(user_id)", onDelete: "SET NULL" },
    flag: { type: "varchar(64)", notNull: true },
    details: { type: "jsonb", notNull: true, default: pgm.func("'{}'::jsonb") },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.createIndex("audit_logs", ["user_id", "created_at"]);
  pgm.createIndex("audit_logs", ["flag", "created_at"]);
};

export const down = (pgm) => {
  pgm.dropTable("audit_logs");
};
