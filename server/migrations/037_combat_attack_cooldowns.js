export const up = (pgm) => {
  pgm.createTable("combat_attack_cooldowns", {
    user_id: {
      type: "uuid",
      primaryKey: true,
      references: "player_profiles(user_id)",
      onDelete: "CASCADE",
    },
    expires_at: { type: "timestamptz", notNull: true },
  });
};

export const down = (pgm) => {
  pgm.dropTable("combat_attack_cooldowns");
};
