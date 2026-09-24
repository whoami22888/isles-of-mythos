export const up = (pgm) => {
  pgm.addColumn("player_profiles", {
    stamina: { type: "real", notNull: true, default: 100 },
    max_stamina: { type: "real", notNull: true, default: 100 },
  });
  pgm.addConstraint("player_profiles", "player_profiles_stamina_range", { check: "stamina >= 0 AND stamina <= max_stamina" });
  pgm.addConstraint("player_profiles", "player_profiles_max_stamina_positive", { check: "max_stamina > 0 AND max_stamina <= 1000" });
};

export const down = (pgm) => {
  pgm.dropConstraint("player_profiles", "player_profiles_stamina_range");
  pgm.dropConstraint("player_profiles", "player_profiles_max_stamina_positive");
  pgm.dropColumn("player_profiles", "stamina");
  pgm.dropColumn("player_profiles", "max_stamina");
};
