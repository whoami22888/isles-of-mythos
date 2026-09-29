export const up=(pgm)=>{
  pgm.addColumn("player_bases",{
    production_processed_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
  });
  pgm.createTable("base_workers",{
    creature_id:{type:"uuid",primaryKey:true,references:"player_creatures(id)",onDelete:"CASCADE"},
    base_id:{type:"uuid",notNull:true,references:"player_bases(id)",onDelete:"CASCADE"},
    building_id:{type:"uuid",notNull:true,references:"base_buildings(id)",onDelete:"CASCADE"},
    task:{type:"varchar(32)",notNull:true},
    assigned_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
  });
  pgm.addConstraint("base_workers","base_workers_building_creature_unique",{unique:["building_id","creature_id"]});
  pgm.addIndex("base_workers",["base_id"]);
  pgm.addIndex("base_workers",["building_id"]);
};
export const down=(pgm)=>{
  pgm.dropTable("base_workers");
  pgm.dropColumn("player_bases","production_processed_at");
};
