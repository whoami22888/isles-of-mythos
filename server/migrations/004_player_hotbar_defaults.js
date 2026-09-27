export const up = (pgm) => {
  const defaultHotbar = '["cutlass","flintlock",null,null,null,null,null,null]'::jsonb;
  pgm.sql(`UPDATE "player_profiles"
    SET "hotbar" = ${defaultHotbar}
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
