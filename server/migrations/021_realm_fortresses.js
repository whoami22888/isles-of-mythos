export const up=(pgm)=>{
  pgm.createTable("realm_fortresses",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    realm_id:{type:"uuid",notNull:true,references:"realms(id)",onDelete:"CASCADE"},
    territory_id:{type:"uuid",notNull:true,references:"territories(id)",onDelete:"CASCADE"},
    name:{type:"varchar(64)",notNull:true},
    level:{type:"integer",notNull:true,default:1},
    health:{type:"integer",notNull:true,default:1000},
    max_health:{type:"integer",notNull:true,default:1000},
    garrison_power:{type:"bigint",notNull:true,default:500},
    active:{type:"boolean",notNull:true,default:true},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("realm_fortresses","realm_fortress_level_check",{check:"level >= 1 AND level <= 10 AND health >= 0 AND max_health > 0 AND health <= max_health AND garrison_power >= 0"});
  pgm.addConstraint("realm_fortresses","realm_fortress_unique",{unique:["territory_id","name"]});
  pgm.createIndex("realm_fortresses",["realm_id","active"]);
  pgm.sql("INSERT INTO realm_fortresses(realm_id,territory_id,name) SELECT r.id,t.id,r.name||' Citadel' FROM realms r JOIN territories t ON t.realm_owner_id=r.id");
};
export const down=(pgm)=>{pgm.dropTable("realm_fortresses");};