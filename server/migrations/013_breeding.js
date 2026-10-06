export const up=(pgm)=>{
  pgm.addColumn("player_creatures",{
    genetics:{type:"jsonb",notNull:true,default:pgm.func("'{}'::jsonb")},
    generation:{type:"integer",notNull:true,default:0},
    parent_a_id:{type:"uuid",references:"player_creatures(id)",onDelete:"SET NULL"},
    parent_b_id:{type:"uuid",references:"player_creatures(id)",onDelete:"SET NULL"},
  });
  pgm.addConstraint("player_creatures","player_creatures_generation_check",{check:"generation >= 0 AND generation <= 1000"});
  pgm.createIndex("player_creatures",["parent_a_id"]);
  pgm.createIndex("player_creatures",["parent_b_id"]);

  pgm.createTable("breeding_jobs",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    base_id:{type:"uuid",notNull:true,references:"player_bases(id)",onDelete:"CASCADE"},
    pen_building_id:{type:"uuid",notNull:true,references:"base_buildings(id)",onDelete:"CASCADE"},
    owner_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    parent_a_id:{type:"uuid",notNull:true,references:"player_creatures(id)",onDelete:"RESTRICT"},
    parent_b_id:{type:"uuid",notNull:true,references:"player_creatures(id)",onDelete:"RESTRICT"},
    started_at:{type:"timestamptz",notNull:true},
    completes_at:{type:"timestamptz",notNull:true},
    status:{type:"varchar(16)",notNull:true,default:"active"},
    offspring_id:{type:"uuid",references:"player_creatures(id)",onDelete:"SET NULL"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
  });
  pgm.addConstraint("breeding_jobs","breeding_jobs_status_check",{check:"status IN ('active','completed','cancelled')"});
  pgm.addConstraint("breeding_jobs","breeding_jobs_parent_distinct",{check:"parent_a_id <> parent_b_id"});
  pgm.addIndex("breeding_jobs",["owner_user_id","status"]);
  pgm.addIndex("breeding_jobs",["pen_building_id","status"],{unique:true,where:"status = 'active'",name:"breeding_jobs_active_pen_unique"});
  pgm.addIndex("breeding_jobs",["parent_a_id","status"],{where:"status = 'active'"});
  pgm.addIndex("breeding_jobs",["parent_b_id","status"],{where:"status = 'active'"});
};

export const down=(pgm)=>{
  pgm.dropTable("breeding_jobs");
  pgm.dropIndex("player_creatures",["parent_b_id"]);
  pgm.dropIndex("player_creatures",["parent_a_id"]);
  pgm.dropConstraint("player_creatures","player_creatures_generation_check");
  pgm.dropColumns("player_creatures",["genetics","generation","parent_a_id","parent_b_id"]);
};
