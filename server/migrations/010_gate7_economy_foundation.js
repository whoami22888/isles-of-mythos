export const up = (pgm) => {
  pgm.addConstraint("player_profiles", "player_profiles_gold_nonnegative", {
    check: "gold >= 0",
  });
};

export const down = (pgm) => {
  pgm.dropConstraint("player_profiles", "player_profiles_gold_nonnegative");
};
