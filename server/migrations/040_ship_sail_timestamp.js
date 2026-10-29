// Server-timed sailing (owner decision D-06/D-07, 2026-10-29): the server, not the client, owns how long a ship has
// been under way. last_sailed_at is the server clock at the ship's previous sail (or creation); ShipStore.sail derives
// elapsed time from it and ignores any client-supplied duration.
// Rollback: `down` drops the column; no other table or constraint depends on it.
export const up = (pgm) => {
  pgm.addColumn("player_ships", {
    last_sailed_at: { type: "timestamptz", notNull: true, default: pgm.func("now()") },
  });
};

export const down = (pgm) => {
  pgm.dropColumn("player_ships", "last_sailed_at");
};
