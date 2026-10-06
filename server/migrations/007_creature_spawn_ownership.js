export const up=(pgm)=>{
  pgm.sql(`DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM player_creatures GROUP BY wild_source_id HAVING COUNT(*) > 1) THEN
      RAISE EXCEPTION 'duplicate wild_source_id values prevent global creature ownership constraint';
    END IF;
  END $$;`);
  pgm.addIndex("player_creatures",["wild_source_id"],{unique:true,name:"player_creatures_wild_source_global_unique"});
};
export const down=(pgm)=>pgm.dropIndex("player_creatures",["wild_source_id"],{name:"player_creatures_wild_source_global_unique"});
