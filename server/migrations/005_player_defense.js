export const up = (pgm) => {
  pgm.addColumn("player_profiles", {
    defense: { type: "real", notNull: true, default: 0 },
  });
  pgm.addConstraint("player_profiles", "player_profiles_defense_range", { check: "defense >= 0 AND defense <= 1000" });
};

export const down = (pgm) => {
  pgm.dropConstraint("player_profiles", "player_profiles_defense_range");
  pgm.dropColumn("player_profiles", "defense");
};
