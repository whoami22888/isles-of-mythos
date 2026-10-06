export const up=(pgm)=>{
  pgm.addColumn("invasion_participants",{
    role:{type:"varchar(16)",notNull:true,default:"damage"},
  });
  pgm.addConstraint("invasion_participants","invasion_participant_role_check",{
    check:"role IN ('tank','damage','support','scout','commander','logistics')",
  });

  pgm.addColumn("invasion_waves",{
    aggro_range:{type:"integer",notNull:true,default:10},
    target_user_id:{type:"uuid",references:"users(id)",onDelete:"SET NULL"},
  });
  pgm.addConstraint("invasion_waves","invasion_wave_aggro_range_check",{
    check:"aggro_range >= 1 AND aggro_range <= 100",
  });
  pgm.createIndex("invasion_waves",["target_user_id"]);
};
export const down=(pgm)=>{
  pgm.dropIndex("invasion_waves",["target_user_id"]);
  pgm.dropConstraint("invasion_waves","invasion_wave_aggro_range_check");
  pgm.dropColumn("invasion_waves","target_user_id");
  pgm.dropColumn("invasion_waves","aggro_range");
  pgm.dropConstraint("invasion_participants","invasion_participant_role_check");
  pgm.dropColumn("invasion_participants","role");
};