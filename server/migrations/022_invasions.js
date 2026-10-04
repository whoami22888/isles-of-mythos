export const up=(pgm)=>{
  pgm.createTable("invasion_threats",{
    territory_id:{type:"uuid",primaryKey:true,references:"territories(id)",onDelete:"CASCADE"},
    threat_level:{type:"integer",notNull:true,default:0},
    victories:{type:"integer",notNull:true,default:0},
    defeats:{type:"integer",notNull:true,default:0},
    last_invasion_at:{type:"timestamptz"},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("invasion_threats","invasion_threats_range",{check:"threat_level >= 0 AND threat_level <= 100000 AND victories >= 0 AND defeats >= 0"});

  pgm.createTable("invasion_schedules",{
    territory_id:{type:"uuid",primaryKey:true,references:"territories(id)",onDelete:"CASCADE"},
    next_run_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP + INTERVAL '300 seconds'")},
    cooldown_seconds:{type:"integer",notNull:true,default:900},
    enabled:{type:"boolean",notNull:true,default:true}
  });
  pgm.addConstraint("invasion_schedules","invasion_schedule_cooldown_check",{check:"cooldown_seconds >= 60 AND cooldown_seconds <= 604800"});

  pgm.createTable("invasions",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    territory_id:{type:"uuid",notNull:true,references:"territories(id)",onDelete:"RESTRICT"},
    source_realm_id:{type:"uuid",references:"realms(id)",onDelete:"SET NULL"},
    source_type:{type:"varchar(24)",notNull:true},
    target_base_id:{type:"uuid",references:"player_bases(id)",onDelete:"SET NULL"},
    phase:{type:"varchar(16)",notNull:true,default:"WARNING"},
    threat_score:{type:"integer",notNull:true},
    started_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    phase_started_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    phase_ends_at:{type:"timestamptz",notNull:true},
    resolved_at:{type:"timestamptz"},
    outcome:{type:"varchar(16)"},
    cooldown_until:{type:"timestamptz"},
    metadata:{type:"jsonb",notNull:true,default:pgm.func("'{}'::jsonb")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("invasions","invasion_phase_check",{check:"phase IN ('WARNING','MUSTER','ARRIVAL','ASSAULT','BATTLE','RESOLUTION','REWARD','COOLDOWN','COMPLETE')"});
  pgm.addConstraint("invasions","invasion_source_check",{check:"source_type IN ('npc_realm','ancient_monster','pirate_fleet','dragon_army','undead_fleet','sea_monster','rival_faction')"});
  pgm.addConstraint("invasions","invasion_threat_check",{check:"threat_score > 0 AND threat_score <= 100000"});
  pgm.createIndex("invasions",["territory_id","phase"]);
  pgm.createIndex("invasions",["phase","phase_ends_at"]);

  pgm.createTable("invasion_waves",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    invasion_id:{type:"uuid",notNull:true,references:"invasions(id)",onDelete:"CASCADE"},
    wave_number:{type:"integer",notNull:true},
    unit_type:{type:"varchar(32)",notNull:true},
    category:{type:"varchar(16)",notNull:true},
    quantity:{type:"integer",notNull:true},
    max_health:{type:"integer",notNull:true},
    current_health:{type:"integer",notNull:true},
    attack:{type:"integer",notNull:true},
    defense:{type:"integer",notNull:true},
    status:{type:"varchar(16)",notNull:true,default:"queued"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("invasion_wave_values_check",{check:"wave_number >= 1 AND quantity > 0 AND max_health > 0 AND current_health >= 0 AND current_health <= max_health AND attack > 0 AND defense >= 0"});
  pgm.addConstraint("invasion_wave_status_check",{check:"status IN ('queued','active','defeated','retreated')"});
  pgm.createIndex("invasion_waves",["invasion_id","wave_number"]);

  pgm.createTable("invasion_participants",{
    invasion_id:{type:"uuid",notNull:true,references:"invasions(id)",onDelete:"CASCADE"},
    user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    army_id:{type:"uuid",references:"armies(id)",onDelete:"SET NULL"},
    contribution:{type:"bigint",notNull:true,default:0},
    actions:{type:"integer",notNull:true,default:0},
    joined_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("invasion_participant_pk",{primaryKey:["invasion_id","user_id"]});
  pgm.addConstraint("invasion_participant_values_check",{check:"contribution >= 0 AND actions >= 0"});

  pgm.createTable("invasion_rewards",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    invasion_id:{type:"uuid",notNull:true,references:"invasions(id)",onDelete:"CASCADE"},
    user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    gold:{type:"bigint",notNull:true,default:0},
    triumph_badges:{type:"bigint",notNull:true,default:0},
    loot:{type:"jsonb",notNull:true,default:pgm.func("'{}'::jsonb")},
    claimed_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("invasion_reward_values_check",{check:"gold >= 0 AND triumph_badges >= 0"});
  pgm.addConstraint("invasion_reward_unique",{unique:["invasion_id","user_id"]});

  pgm.createTable("invasion_consequences",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    invasion_id:{type:"uuid",notNull:true,references:"invasions(id)",onDelete:"CASCADE"},
    territory_id:{type:"uuid",notNull:true,references:"territories(id)",onDelete:"RESTRICT"},
    base_id:{type:"uuid",references:"player_bases(id)",onDelete:"SET NULL"},
    user_id:{type:"uuid",references:"users(id)",onDelete:"SET NULL"},
    consequence_type:{type:"varchar(32)",notNull:true},
    severity:{type:"integer",notNull:true},
    payload:{type:"jsonb",notNull:true,default:pgm.func("'{}'::jsonb")},
    applied_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("invasion_consequence_severity",{check:"severity >= 0 AND severity <= 100"});
  pgm.createIndex("invasion_consequences",["territory_id","applied_at"]);

  pgm.sql("INSERT INTO invasion_threat(territory_id) SELECT id FROM territories ON CONFLICT DO NOTHING");
  pgm.sql("INSERT INTO invasion_schedules(territory_id) SELECT id FROM territories ON CONFLICT DO NOTHING");
};
export const down=(pgm)=>{
  pgm.dropTable("invasion_consequences");pgm.dropTable("invasion_rewards");pgm.dropTable("invasion_participants");pgm.dropTable("invasion_waves");pgm.dropTable("invasions");pgm.dropTable("invasion_schedules");pgm.dropTable("invasion_threats");
};