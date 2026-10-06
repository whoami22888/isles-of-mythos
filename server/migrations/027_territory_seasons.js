export const up=(pgm)=>{
  pgm.createTable("territory_seasons",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    season_number:{type:"integer",notNull:true,unique:true},
    name:{type:"varchar(128)",notNull:true},
    status:{type:"varchar(16)",notNull:true,default:"active"},
    starts_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    ends_at:{type:"timestamptz",notNull:true},
    resolved_at:{type:"timestamptz"},
    winner_type:{type:"varchar(16)"},
    winner_id:{type:"uuid"},
    state:{type:"jsonb",notNull:true,default:"{}"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("territory_seasons","territory_seasons_status_check",{check:"status IN ('active','resolved')"});
  pgm.addConstraint("territory_seasons","territory_seasons_winner_type_check",{check:"winner_type IS NULL OR winner_type IN ('realm','guild')"});
  pgm.addConstraint("territory_seasons","territory_seasons_dates_check",{check:"ends_at > starts_at"});
  pgm.createIndex("territory_seasons",["status","ends_at"]);

  pgm.createTable("territory_season_standings",{
    season_id:{type:"uuid",notNull:true,references:"territory_seasons(id)",onDelete:"CASCADE"},
    actor_type:{type:"varchar(16)",notNull:true},
    actor_id:{type:"uuid",notNull:true},
    points:{type:"bigint",notNull:true,default:0},
    territories_controlled:{type:"integer",notNull:true,default:0},
    wins:{type:"integer",notNull:true,default:0},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("territory_season_standings","territory_season_standings_pk",{primaryKey:["season_id","actor_type","actor_id"]});
  pgm.addConstraint("territory_season_standings","territory_season_standings_actor_check",{check:"actor_type IN ('realm','guild')"});
  pgm.addConstraint("territory_season_standings","territory_season_standings_values_check",{check:"points >= 0 AND territories_controlled >= 0 AND wins >= 0"});
  pgm.createIndex("territory_season_standings",["season_id","points"]);

  pgm.sql(`INSERT INTO territory_seasons(season_number,name,ends_at,state)
    VALUES(1,'Rise of the Sunken Kingdom',CURRENT_TIMESTAMP+INTERVAL '30 days','{"version":1}')
    ON CONFLICT(season_number) DO NOTHING`);
};

export const down=(pgm)=>{
  pgm.dropTable("territory_season_standings");
  pgm.dropTable("territory_seasons");
};