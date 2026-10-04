export const up=(pgm)=>{
  pgm.addColumn("player_ships",{fire_until:{type:"timestamptz",default:null},fire_damage:{type:"integer",notNull:true,default:0},retreat_until:{type:"timestamptz",default:null}});
  pgm.addConstraint("player_ships","player_ships_fire_damage_check",{check:"fire_damage >= 0"});
  pgm.addColumn("naval_combat_events",{action_type:{type:"varchar(32)",notNull:true,default:"cannon"}});
  pgm.createTable("naval_world_state",{id:{type:"integer",primaryKey:true},wind_x:{type:"double precision",notNull:true,default:1},wind_y:{type:"double precision",notNull:true,default:0},updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}});
  pgm.sql("INSERT INTO naval_world_state(id,wind_x,wind_y) VALUES (1,1,0) ON CONFLICT (id) DO NOTHING");
};
export const down=(pgm)=>{pgm.dropTable("naval_world_state");pgm.dropColumn("naval_combat_events","action_type");pgm.dropConstraint("player_ships","player_ships_fire_damage_check");pgm.dropColumn("player_ships",["fire_until","fire_damage","retreat_until"]);};