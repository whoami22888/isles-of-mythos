export const up = (pgm) => {
  pgm.addColumn("player_profiles", {
    triumph_badges: { type: "bigint", notNull: true, default: 0 },
  });
  pgm.addConstraint("player_profiles", "player_profiles_triumph_badges_nonnegative", {
    check: "triumph_badges >= 0",
  });
};

export const down = (pgm) => {
  pgm.dropConstraint("player_profiles", "player_profiles_triumph_badges_nonnegative");
  pgm.dropColumn("player_profiles", "triumph_badges");
};
