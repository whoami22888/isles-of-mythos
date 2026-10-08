export const up=(pgm)=>{
  pgm.createTable("armies",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    owner_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    name:{type:"varchar(64)",notNull:true},
    assignment:{type:"varchar(24)",notNull:true,default:"garrison"},
    commander_user_id:{type:"uuid",references:"users(id)",onDelete:"SET NULL"},
    status:{type:"varchar(16)",notNull:true,default:"ready"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("armies","armies_assignment_check",{check:"assignment IN ('garrison','patrol','expedition','resource_protection','guild_mission','realm_warfare','invasion','convoy','naval')"});
  pgm.addConstraint("armies","armies_status_check",{check:"status IN ('ready','training','deployed','wounded','retreating')"});
  pgm.createIndex("armies",["owner_user_id","status"]);

  pgm.createTable("army_units",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    army_id:{type:"uuid",notNull:true,references:"armies(id)",onDelete:"CASCADE"},
    unit_type:{type:"varchar(32)",notNull:true},
    source_creature_id:{type:"uuid",references:"player_creatures(id)",onDelete:"SET NULL"},
    category:{type:"varchar(16)",notNull:true},
    quantity:{type:"integer",notNull:true,default:1},
    health:{type:"integer",notNull:true},
    max_health:{type:"integer",notNull:true},
    attack:{type:"integer",notNull:true},
    defense:{type:"integer",notNull:true},
    range:{type:"integer",notNull:true,default:1},
    speed:{type:"integer",notNull:true,default:1},
    ability_ids:{type:"jsonb",notNull:true,default:pgm.func("'[]'::jsonb")},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("army_units","army_units_quantity_check",{check:"quantity > 0"});
  pgm.addConstraint("army_units","army_units_health_check",{check:"health >= 0 AND max_health > 0 AND health <= max_health AND attack > 0 AND defense >= 0 AND range > 0 AND speed > 0"});
  pgm.createIndex("army_units",["army_id"]);

  pgm.createTable("army_garrisons",{
    base_id:{type:"uuid",notNull:true,references:"player_bases(id)",onDelete:"CASCADE"},
    army_id:{type:"uuid",notNull:true,references:"armies(id)",onDelete:"CASCADE"},
    role:{type:"varchar(24)",notNull:true,default:"defense"},
    stationed_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("army_garrisons","army_garrisons_pk",{primaryKey:["base_id","army_id"]});
  pgm.createIndex("army_garrisons",["army_id"]);

  pgm.createTable("army_formations",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    army_id:{type:"uuid",notNull:true,references:"armies(id)",onDelete:"CASCADE"},
    name:{type:"varchar(32)",notNull:true},
    formation_type:{type:"varchar(24)",notNull:true},
    layout:{type:"jsonb",notNull:true,default:pgm.func("'{}'::jsonb")},
    is_active:{type:"boolean",notNull:true,default:false},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("army_formations","army_formations_type_check",{check:"formation_type IN ('line','wedge','column','box','ranged','siege','custom')"});
  pgm.createIndex("army_formations",["army_id","is_active"]);

  pgm.createTable("army_training_queue",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    army_id:{type:"uuid",notNull:true,references:"armies(id)",onDelete:"CASCADE"},
    unit_type:{type:"varchar(32)",notNull:true},
    quantity:{type:"integer",notNull:true},
    completes_at:{type:"timestamptz",notNull:true},
    status:{type:"varchar(16)",notNull:true,default:"training"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("army_training_queue","army_training_status_check",{check:"status IN ('training','completed','cancelled')"});
  pgm.addConstraint("army_training_queue","army_training_quantity_check",{check:"quantity > 0"});

  pgm.createTable("army_battles",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    attacker_army_id:{type:"uuid",notNull:true,references:"armies(id)",onDelete:"RESTRICT"},
    defender_army_id:{type:"uuid",references:"armies(id)",onDelete:"RESTRICT"},
    owner_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    status:{type:"varchar(16)",notNull:true,default:"active"},
    turn:{type:"integer",notNull:true,default:1},
    seed:{type:"bigint",notNull:true},
    target_x:{type:"double precision",notNull:true,default:0},
    target_y:{type:"double precision",notNull:true,default:0},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("army_battles","army_battles_status_check",{check:"status IN ('active','attacker_won','defender_won','retreated')"});
  pgm.addConstraint("army_battles","army_battles_turn_check",{check:"turn >= 1"});

  pgm.createTable("battle_units",{
    battle_id:{type:"uuid",notNull:true,references:"army_battles(id)",onDelete:"CASCADE"},
    army_unit_id:{type:"uuid",notNull:true,references:"army_units(id)",onDelete:"CASCADE"},
    side:{type:"varchar(16)",notNull:true},
    deployed:{type:"boolean",notNull:true,default:false},
    formation_slot:{type:"integer"},
    current_health:{type:"integer",notNull:true},
    retreating:{type:"boolean",notNull:true,default:false}
  });
  pgm.addConstraint("battle_units","battle_units_pk",{primaryKey:["battle_id","army_unit_id"]});
  pgm.addConstraint("battle_units","battle_units_side_check",{check:"side IN ('attacker','defender')"});
  pgm.addConstraint("battle_units","battle_units_health_check",{check:"current_health >= 0"});

  pgm.createTable("commander_orders",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    army_id:{type:"uuid",references:"armies(id)",onDelete:"CASCADE"},
    battle_id:{type:"uuid",references:"army_battles(id)",onDelete:"CASCADE"},
    commander_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    order_type:{type:"varchar(24)",notNull:true},
    target_unit_id:{type:"uuid",references:"army_units(id)",onDelete:"SET NULL"},
    target_x:{type:"double precision"},
    target_y:{type:"double precision"},
    payload:{type:"jsonb",notNull:true,default:pgm.func("'{}'::jsonb")},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("commander_orders","commander_orders_target_check",{check:"army_id IS NOT NULL OR battle_id IS NOT NULL"});
  pgm.createIndex("commander_orders",["army_id","created_at"]);
  pgm.createIndex("commander_orders",["battle_id","created_at"]);

  pgm.createTable("base_defensive_structures",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    base_id:{type:"uuid",notNull:true,references:"player_bases(id)",onDelete:"CASCADE"},
    structure_type:{type:"varchar(24)",notNull:true},
    grid_x:{type:"integer",notNull:true},
    grid_y:{type:"integer",notNull:true},
    level:{type:"integer",notNull:true,default:1},
    health:{type:"integer",notNull:true},
    max_health:{type:"integer",notNull:true},
    ammo:{type:"integer",notNull:true,default:0},
    active:{type:"boolean",notNull:true,default:true},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("base_defensive_structures","base_defensive_structure_type_check",{check:"structure_type IN ('archer_tower','musket_tower','cannon_tower','magic_tower','mermaid_tower','dragon_tower','wall','gate','spike_trap','fire_trap','water_trap','net_trap','explosive_barrel','magic_trap')"});
  pgm.addConstraint("base_defensive_structures","base_defensive_structure_health_check",{check:"level >= 1 AND level <= 7 AND health >= 0 AND max_health > 0 AND health <= max_health AND ammo >= 0"});
  pgm.createIndex("base_defensive_structures",["base_id","active"]);

  pgm.createTable("army_commander_nominations",{
    guild_id:{type:"uuid",notNull:true,references:"guilds(id)",onDelete:"CASCADE"},
    user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    appointed_by:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("army_commander_nominations","army_commander_nominations_pk",{primaryKey:["guild_id","user_id"]});
};

export const down=(pgm)=>{
  pgm.dropTable("army_commander_nominations");
  pgm.dropTable("base_defensive_structures");
  pgm.dropTable("commander_orders");
  pgm.dropTable("battle_units");
  pgm.dropTable("army_battles");
  pgm.dropTable("army_training_queue");
  pgm.dropTable("army_formations");
  pgm.dropTable("army_garrisons");
  pgm.dropTable("army_units");
  pgm.dropTable("armies");
};
