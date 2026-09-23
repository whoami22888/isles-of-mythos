export const up = (pgm) => {
  pgm.createExtension("pgcrypto", { ifNotExists: true });

  pgm.createTable("users", {
    id: {
      type: "uuid",
      primaryKey: true,
      default: pgm.func("gen_random_uuid()"),
    },
    username: {
      type: "varchar(32)",
      notNull: true,
    },
    email: {
      type: "varchar(254)",
      notNull: true,
    },
    password_hash: {
      type: "text",
      notNull: true,
    },
    created_at: {
      type: "timestamptz",
      notNull: true,
      default: pgm.func("CURRENT_TIMESTAMP"),
    },
    updated_at: {
      type: "timestamptz",
      notNull: true,
      default: pgm.func("CURRENT_TIMESTAMP"),
    },
  });

  pgm.addConstraint("users", "users_username_unique", {
    unique: ["username"],
  });

  pgm.addConstraint("users", "users_email_unique", {
    unique: ["email"],
  });
};

export const down = (pgm) => {
  pgm.dropTable("users");
};
