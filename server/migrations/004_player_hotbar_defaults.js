export const up = (pgm) => {
  pgm.sql(`UPDATE "player_profiles"
    SET "hotbar" = '[\"cutlass\",\"flintlock\",null,null,null,null,null,null]'::jsonb
    WHERE "hotbar" = '[null,null,null,null,null,null,null,null]'::jsonb`);
  pgm.alterColumn("player_profiles", "hotbar", {
    default: pgm.func("'[\"cutlass\",\"flintlock\",null,null,null,null,null,null]'::jsonb"),
  });
};

export const down = (pgm) => {
  pgm.alterColumn("player_profiles", "hotbar", {
    default: pgm.func("'[null,null,null,null,null,null,null,null]'::jsonb"),
  });
};
