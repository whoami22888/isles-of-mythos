export const up=(pgm)=>{
  pgm.createTable("player_ships",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    owner_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    name:{type:"varchar(64)",notNull:true},
    ship_class:{type:"varchar(32)",notNull:true},
    hull:{type:"integer",notNull:true},
    max_hull:{type:"integer",notNull:true},
    armor:{type:"integer",notNull:true},
    speed:{type:"double precision",notNull:true},
    turn_rate:{type:"double precision",notNull:true},
    cargo_capacity:{type:"integer",notNull:true},
    crew_capacity:{type:"integer",notNull:true},
    cannon_count:{type:"integer",notNull:true},
    sail_power:{type:"integer",notNull:true},
    fuel:{type:"integer",notNull:true},
    max_fuel:{type:"integer",notNull:true},
    x:{type:"double precision",notNull:true,default:0},
    y:{type:"double precision",notNull:true,default:0},
    heading:{type:"double precision",notNull:true,default:0},
    status:{type:"varchar(16)",notNull:true,default:"active"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
  });
  pgm.addConstraint("player_ships","player_ships_hull_check",{check:"hull >= 0 AND max_hull > 0 AND hull <= max_hull"});
  pgm.addConstraint("player_ships","player_ships_stat_check",{check:"armor >= 0 AND speed > 0 AND turn_rate > 0 AND cargo_capacity > 0 AND crew_capacity >= 1 AND cannon_count >= 0 AND sail_power > 0 AND fuel >= 0 AND max_fuel > 0 AND fuel <= max_fuel"});
  pgm.addConstraint("player_ships","player_ships_status_check",{check:"status IN ('active','destroyed','docked')"});
  pgm.createIndex("player_ships",["owner_user_id","status"]);

  pgm.createTable("ship_inventory",{
    ship_id:{type:"uuid",notNull:true,references:"player_ships(id)",onDelete:"CASCADE"},
    item_id:{type:"varchar(128)",notNull:true},
    quantity:{type:"bigint",notNull:true,default:0},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
  });
  pgm.addConstraint("ship_inventory","ship_inventory_pk",{primaryKey:["ship_id","item_id"]});
  pgm.addConstraint("ship_inventory","ship_inventory_quantity_check",{check:"quantity >= 0"});
  pgm.createIndex("ship_inventory",["ship_id"]);

  pgm.createTable("ship_crew",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    ship_id:{type:"uuid",notNull:true,references:"player_ships(id)",onDelete:"CASCADE"},
    creature_id:{type:"uuid",references:"player_creatures(id)",onDelete:"SET NULL"},
    owner_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    npc_type:{type:"varchar(32)",notNull:true,default:"creature"},
    role:{type:"varchar(32)",notNull:true},
    skill:{type:"integer",notNull:true,default:1},
    morale:{type:"integer",notNull:true,default:100},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
  });
  pgm.addConstraint("ship_crew","ship_crew_skill_check",{check:"skill >= 1 AND skill <= 100"});
  pgm.addConstraint("ship_crew","ship_crew_morale_check",{check:"morale >= 0 AND morale <= 100"});
  pgm.createIndex("ship_crew",["ship_id"]);
  pgm.addIndex("ship_crew",["creature_id"],{unique:true,where:"creature_id IS NOT NULL",name:"ship_crew_creature_unique"});

  pgm.createTable("naval_combat_events",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    attacker_ship_id:{type:"uuid",notNull:true,references:"player_ships(id)",onDelete:"CASCADE"},
    defender_ship_id:{type:"uuid",notNull:true,references:"player_ships(id)",onDelete:"CASCADE"},
    attacker_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    defender_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    damage:{type:"integer",notNull:true},
    attacker_hull_after:{type:"integer",notNull:true},
    defender_hull_after:{type:"integer",notNull:true},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
  });
  pgm.addConstraint("naval_combat_events","naval_combat_events_damage_check",{check:"damage > 0"});
  pgm.createIndex("naval_combat_events",["attacker_ship_id","created_at"]);
  pgm.createIndex("naval_combat_events",["defender_ship_id","created_at"]);
};

export const down=(pgm)=>{
  pgm.dropTable("naval_combat_events");
  pgm.dropIndex("ship_crew",["creature_id"],{name:"ship_crew_creature_unique"});
  pgm.dropIndex("ship_crew",["ship_id"]);
  pgm.dropTable("ship_crew");
  pgm.dropIndex("ship_inventory",["ship_id"]);
  pgm.dropTable("ship_inventory");
  pgm.dropIndex("player_ships",["owner_user_id","status"]);
  pgm.dropTable("player_ships");
};
