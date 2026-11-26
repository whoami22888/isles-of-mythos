// Prompt 024 NPC shop hire contracts and published daily upkeep. Does not touch 029/036.
export const up = (pgm) => {
  pgm.createTable("npc_crew_contracts", {
    id: { type: "uuid", primaryKey: true, default: pgm.func("gen_random_uuid()") },
    user_id: { type: "uuid", notNull: true, references: "player_profiles(user_id)", onDelete: "CASCADE" },
    crew_type: { type: "varchar(32)", notNull: true },
    hire_cost: { type: "bigint", notNull: true },
    daily_upkeep: { type: "bigint", notNull: true },
    hired_at: { type: "timestamptz", notNull: true, default: pgm.func("CURRENT_TIMESTAMP") },
  });
  pgm.addConstraint("npc_crew_contracts", "npc_crew_contracts_type_check", {
    check: "crew_type IN ('pirate_sailor', 'specialist_officer')",
  });
  pgm.addConstraint("npc_crew_contracts", "npc_crew_contracts_costs_nonnegative", {
    check: "hire_cost >= 0 AND daily_upkeep >= 0",
  });
  pgm.createIndex("npc_crew_contracts", ["user_id", "hired_at"]);
};

export const down = (pgm) => {
  pgm.dropTable("npc_crew_contracts");
};
