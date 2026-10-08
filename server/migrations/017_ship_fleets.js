export const up=(pgm)=>{
  pgm.createTable("ship_fleets",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    owner_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    name:{type:"varchar(64)",notNull:true},
    commander_ship_id:{type:"uuid",references:"player_ships(id)",onDelete:"RESTRICT"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.createTable("ship_fleet_members",{
    fleet_id:{type:"uuid",notNull:true,references:"ship_fleets(id)",onDelete:"CASCADE"},
    ship_id:{type:"uuid",notNull:true,unique:true,references:"player_ships(id)",onDelete:"CASCADE"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("ship_fleet_members","ship_fleet_members_pk",{primaryKey:["fleet_id","ship_id"]});
  pgm.createIndex("ship_fleets",["owner_user_id"]);
  pgm.createIndex("ship_fleet_members",["fleet_id"]);
};
export const down=(pgm)=>{
  pgm.dropIndex("ship_fleet_members",["fleet_id"]);
  pgm.dropTable("ship_fleet_members");
  pgm.dropIndex("ship_fleets",["owner_user_id"]);
  pgm.dropTable("ship_fleets");
};