export const up=(pgm)=>{
  pgm.createTable("economy_transactions",{
    transaction_id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    user_id:{type:"uuid",notNull:true,references:"player_profiles(user_id)",onDelete:"CASCADE"},
    operation:{type:"varchar(64)",notNull:true},
    gold_before:{type:"bigint",notNull:true},
    gold_after:{type:"bigint",notNull:true},
    triumph_badges_before:{type:"bigint",notNull:true},
    triumph_badges_after:{type:"bigint",notNull:true},
    inventory_before:{type:"jsonb",notNull:true},
    inventory_after:{type:"jsonb",notNull:true},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.createIndex("economy_transactions",["user_id","created_at"]);
  pgm.createIndex("economy_transactions",["operation","created_at"]);
};
export const down=(pgm)=>{
  pgm.dropTable("economy_transactions");
};
