// Prompt 029 offline production clock. Intended for the test/CI database only.
// Do not apply this migration to production.
export const up = (pgm) => {
  pgm.addColumns("player_profiles", {
    last_online_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
};

export const down = (pgm) => {
  pgm.dropColumns("player_profiles", ["last_online_at"]);
};
