export const up=(pgm)=>{
  pgm.createTable("player_bases",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    owner_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    name:{type:"varchar(64)",notNull:true},
    x:{type:"integer",notNull:true},
    y:{type:"integer",notNull:true},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
  });
  pgm.addConstraint("player_bases","player_bases_owner_unique",{unique:["owner_user_id"]});
  pgm.createTable("base_buildings",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    base_id:{type:"uuid",notNull:true,references:"player_bases(id)",onDelete:"CASCADE"},
    type:{type:"varchar(32)",notNull:true},
    level:{type:"integer",notNull:true,default:1},
    grid_x:{type:"integer",notNull:true},
    grid_y:{type:"integer",notNull:true},
    active:{type:"boolean",notNull:true,default:true},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
  });
  pgm.addConstraint("base_buildings","base_buildings_level_check",{check:"level >= 1 AND level <= 7"});
  pgm.addConstraint("base_buildings_grid_x_check",{check:"grid_x >= -128 AND grid_x <= 128"});
  pgm.addConstraint("base_buildings_grid_y_check",{check:"grid_y >= -128 AND grid_y <= 128"});
  pgm.addConstraint("base_buildings_position_unique",{unique:["base_id","grid_x","grid_y"]});
  pgm.createTable("base_storage",{
    base_id:{type:"uuid",notNull:true,references:"player_bases(id)",onDelete:"CASCADE"},
    resource_key:{type:"varchar(64)",notNull:true},
    quantity:{type:"bigint",notNull:true,default:0},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
  });
  pgm.addConstraint("base_storage","base_storage_pk",{primaryKey:["base_id","resource_key"]});
  pgm.addConstraint("base_storage_quantity_check",{check:"quantity >= 0"});
  pgm.createTable("base_work_priorities",{
    base_id:{type:"uuid",notNull:true,references:"player_bases(id)",onDelete:"CASCADE"},
    priority_index:{type:"integer",notNull:true},
    priority:{type:"varchar(32)",notNull:true},
  });
  pgm.addConstraint("base_work_priorities_pk",{primaryKey:["base_id","priority_index"]});
  pgm.createTable("base_permissions",{
    base_id:{type:"uuid",notNull:true,references:"player_bases(id)",onDelete:"CASCADE"},
    user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    permission:{type:"varchar(32)",notNull:true},
  });
  pgm.addConstraint("base_permissions_pk",{primaryKey:["base_id","user_id","permission"]});
};
export const down=(pgm)=>{
  pgm.dropTable("base_permissions");
  pgm.dropTable("base_work_priorities");
  pgm.dropTable("base_storage");
  pgm.dropTable("base_buildings");
  pgm.dropTable("player_bases");
};