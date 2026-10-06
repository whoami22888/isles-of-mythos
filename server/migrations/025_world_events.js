export const up=(pgm)=>{
  pgm.createTable("world_events",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    event_type:{type:"varchar(32)",notNull:true},
    status:{type:"varchar(16)",notNull:true,default:"active"},
    region_id:{type:"integer"},
    center_x:{type:"integer",notNull:true},
    center_y:{type:"integer",notNull:true},
    max_health:{type:"bigint"},
    current_health:{type:"bigint"},
    state:{type:"jsonb",notNull:true,default:"{}"},
    seed:{type:"bigint",notNull:true},
    started_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    ends_at:{type:"timestamptz",notNull:true},
    completed_at:{type:"timestamptz"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("world_events","world_events_type_check",{check:"event_type IN ('world_boss','treasure_storm','ghost_fleet','kraken','dragon_migration')"});
  pgm.addConstraint("world_events","world_events_status_check",{check:"status IN ('active','completed','expired')"});
  pgm.addConstraint("world_events","world_events_health_check",{check:"(max_health IS NULL AND current_health IS NULL) OR (max_health > 0 AND current_health >= 0 AND current_health <= max_health)"});
  pgm.createIndex("world_events",["status","ends_at"]);
  pgm.createIndex("world_events",["event_type","status","region_id"]);

  pgm.createTable("world_event_contributions",{
    event_id:{type:"uuid",notNull:true,references:"world_events(id)",onDelete:"CASCADE"},
    user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    contribution:{type:"bigint",notNull:true,default:0},
    actions:{type:"integer",notNull:true,default:0},
    last_contributed_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("world_event_contributions","world_event_contributions_pk",{primaryKey:["event_id","user_id"]});
  pgm.addConstraint("world_event_contributions","world_event_contribution_check",{check:"contribution >= 0 AND actions >= 0"});
  pgm.createIndex("world_event_contributions",["user_id","event_id"]);

  pgm.createTable("world_event_rewards",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    event_id:{type:"uuid",notNull:true,references:"world_events(id)",onDelete:"CASCADE"},
    user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    reward:{type:"jsonb",notNull:true},
    claimed_at:{type:"timestamptz"}
  });
  pgm.addConstraint("world_event_rewards","world_event_rewards_unique",{unique:["event_id","user_id"]});
  pgm.createIndex("world_event_rewards",["user_id","claimed_at"]);

  pgm.createTable("world_event_effects",{
    event_id:{type:"uuid",notNull:true,references:"world_events(id)",onDelete:"CASCADE"},
    effect_key:{type:"varchar(64)",notNull:true},
    effect_value:{type:"jsonb",notNull:true},
    expires_at:{type:"timestamptz",notNull:true}
  });
  pgm.addConstraint("world_event_effects","world_event_effects_pk",{primaryKey:["event_id","effect_key"]});
  pgm.createIndex("world_event_effects",["expires_at"]);
};

export const down=(pgm)=>{
  pgm.dropTable("world_event_effects");
  pgm.dropTable("world_event_rewards");
  pgm.dropTable("world_event_contributions");
  pgm.dropTable("world_events");
};