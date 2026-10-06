export const up=(pgm)=>{
  pgm.addColumn("player_bases",{
    maximum_creatures:{type:"integer",notNull:true,default:20},
    maximum_workers:{type:"integer",notNull:true,default:10},
    maximum_breeding_slots:{type:"integer",notNull:true,default:1},
  });
  pgm.addConstraint("player_bases","player_bases_population_limits_check",{check:"maximum_creatures >= 1 AND maximum_creatures <= 10000 AND maximum_workers >= 0 AND maximum_workers <= 1000 AND maximum_breeding_slots >= 0 AND maximum_breeding_slots <= 1000"});
  pgm.createIndex("breeding_jobs",["base_id","status"]);
};
export const down=(pgm)=>{pgm.dropIndex("breeding_jobs",["base_id","status"]);pgm.dropConstraint("player_bases","player_bases_population_limits_check");pgm.dropColumns("player_bases",["maximum_creatures","maximum_workers","maximum_breeding_slots"]);};
