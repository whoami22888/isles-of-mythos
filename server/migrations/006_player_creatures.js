export const up=(pgm)=>{
  pgm.createTable("player_creatures",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    owner_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    wild_source_id:{type:"varchar(128)",notNull:true},
    species:{type:"varchar(32)",notNull:true},
    nickname:{type:"varchar(32)"},
    level:{type:"integer",notNull:true,default:1},
    xp:{type:"bigint",notNull:true,default:0},
    health:{type:"real",notNull:true},
    max_health:{type:"real",notNull:true},
    attack:{type:"real",notNull:true},
    defense:{type:"real",notNull:true},
    element:{type:"varchar(16)",notNull:true},
    ability_ids:{type:"jsonb",notNull:true,default:pgm.func("'[]'::jsonb")},
    tame_progress:{type:"integer",notNull:true,default:0},
    party_slot:{type:"integer"},
    ai_mode:{type:"varchar(16)",notNull:true,default:"follow"},
    x:{type:"real",notNull:true},
    y:{type:"real",notNull:true},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.sql("UPDATE player_profiles SET inventory = COALESCE(inventory, '{}'::jsonb) || CASE WHEN COALESCE(inventory, '{}'::jsonb) ? 'capture.orb' THEN '{}'::jsonb ELSE jsonb_build_object('capture.orb', 3) END || CASE WHEN COALESCE(inventory, '{}'::jsonb) ? 'creature.feed' THEN '{}'::jsonb ELSE jsonb_build_object('creature.feed', 4) END WHERE inventory IS NULL OR NOT (COALESCE(inventory, '{}'::jsonb) ? 'capture.orb') OR NOT (COALESCE(inventory, '{}'::jsonb) ? 'creature.feed')");
  pgm.addConstraint("player_creatures","player_creatures_level_range",{check:"level>=1 AND level<=100"});
  pgm.addConstraint("player_creatures","player_creatures_tame_range",{check:"tame_progress>=0 AND tame_progress<=100"});
  pgm.addConstraint("player_creatures","player_creatures_party_range",{check:"party_slot IS NULL OR (party_slot>=0 AND party_slot<3)"});
  pgm.addConstraint("player_creatures","player_creatures_ai_mode",{check:"ai_mode IN ('follow','assist','stay')"});
  pgm.addConstraint("player_creatures","player_creatures_wild_source_unique",{unique:["owner_user_id","wild_source_id"]});
  pgm.createIndex("player_creatures",["owner_user_id","party_slot"],{unique:true,where:"party_slot IS NOT NULL"});
};
export const down=(pgm)=>pgm.dropTable("player_creatures");
