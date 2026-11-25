// Persisted Mythos companion mood/care and state. Yield and XP multipliers stay
// server-authoritative. Rollback: `down` drops the new columns. Does not touch 029/036.
export const up = (pgm) => {
  pgm.addColumns("player_creatures", {
    mood: { type: "numeric(5,2)", notNull: true, default: 0 },
    companion_state: { type: "varchar(16)", notNull: true, default: "tamed_follow" },
  });
  pgm.addConstraint("player_creatures", "player_creatures_mood_range", {
    check: "mood >= 0 AND mood <= 100",
  });
  pgm.addConstraint("player_creatures", "player_creatures_companion_state", {
    check: "companion_state IN ('wild', 'tamed_follow', 'tamed_work', 'resting')",
  });
  pgm.sql("UPDATE player_creatures SET companion_state='wild' WHERE tame_progress < 100");
};

export const down = (pgm) => {
  pgm.dropConstraint("player_creatures", "player_creatures_companion_state");
  pgm.dropConstraint("player_creatures", "player_creatures_mood_range");
  pgm.dropColumns("player_creatures", ["mood", "companion_state"]);
};
