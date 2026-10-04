export const up=(pgm)=>{
  pgm.createTable("guilds",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    name:{type:"varchar(64)",notNull:true},
    tag:{type:"varchar(8)",notNull:true},
    leader_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"RESTRICT"},
    level:{type:"integer",notNull:true,default:1},
    experience:{type:"bigint",notNull:true,default:0},
    treasury:{type:"bigint",notNull:true,default:0},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("guilds","guilds_name_unique",{unique:["name"]});
  pgm.addConstraint("guilds","guilds_tag_unique",{unique:["tag"]});
  pgm.addConstraint("guilds","guilds_level_check",{check:"level >= 1"});
  pgm.addConstraint("guilds","guilds_experience_check",{check:"experience >= 0"});
  pgm.addConstraint("guilds","guilds_treasury_check",{check:"treasury >= 0"});
  pgm.createTable("guild_members",{
    guild_id:{type:"uuid",notNull:true,references:"guilds(id)",onDelete:"CASCADE"},
    user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    rank:{type:"varchar(16)",notNull:true,default:"recruit"},
    joined_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("guild_members","guild_members_pk",{primaryKey:["guild_id","user_id"]});
  pgm.addConstraint("guild_members","guild_members_rank_check",{check:"rank IN ('master','officer','veteran','member','recruit')"});
  pgm.createIndex("guild_members",["user_id"],{unique:true});
  pgm.createTable("guild_permissions",{
    guild_id:{type:"uuid",notNull:true,references:"guilds(id)",onDelete:"CASCADE"},
    rank:{type:"varchar(16)",notNull:true},
    permission:{type:"varchar(32)",notNull:true},
    enabled:{type:"boolean",notNull:true,default:true}
  });
  pgm.addConstraint("guild_permissions","guild_permissions_pk",{primaryKey:["guild_id","rank","permission"]});
  pgm.addConstraint("guild_permissions","guild_permissions_rank_check",{check:"rank IN ('master','officer','veteran','member','recruit')"});
  pgm.createTable("guild_invitations",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    guild_id:{type:"uuid",notNull:true,references:"guilds(id)",onDelete:"CASCADE"},
    inviter_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    invitee_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    status:{type:"varchar(16)",notNull:true,default:"pending"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    responded_at:{type:"timestamptz",default:null}
  });
  pgm.addConstraint("guild_invitations","guild_invitations_status_check",{check:"status IN ('pending','accepted','declined')"});
  pgm.createIndex("guild_invitations",["guild_id","invitee_user_id"]);
  pgm.createIndex("guild_invitations",["invitee_user_id","status"]);
  pgm.createTable("guild_bank_items",{
    guild_id:{type:"uuid",notNull:true,references:"guilds(id)",onDelete:"CASCADE"},
    item_id:{type:"varchar(128)",notNull:true},
    quantity:{type:"bigint",notNull:true,default:0},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("guild_bank_items","guild_bank_items_pk",{primaryKey:["guild_id","item_id"]});
  pgm.addConstraint("guild_bank_items","guild_bank_items_quantity_check",{check:"quantity >= 0"});
  pgm.createTable("guild_bank_transactions",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    guild_id:{type:"uuid",notNull:true,references:"guilds(id)",onDelete:"CASCADE"},
    user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    action_type:{type:"varchar(32)",notNull:true},
    item_id:{type:"varchar(128)"},
    quantity:{type:"bigint",notNull:true,default:0},
    gold_before:{type:"bigint",notNull:true,default:0},
    gold_after:{type:"bigint",notNull:true,default:0},
    metadata:{type:"jsonb",notNull:true,default:pgm.func("'{}'::jsonb")},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("guild_bank_transactions","guild_bank_transactions_quantity_check",{check:"quantity >= 0"});
  pgm.addConstraint("guild_bank_transactions","guild_bank_transactions_gold_check",{check:"gold_before >= 0 AND gold_after >= 0"});
  pgm.createIndex("guild_bank_transactions",["guild_id","created_at"]);
  pgm.createTable("guild_infrastructure",{
    guild_id:{type:"uuid",notNull:true,references:"guilds(id)",onDelete:"CASCADE"},
    structure_type:{type:"varchar(32)",notNull:true},
    level:{type:"integer",notNull:true,default:1},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("guild_infrastructure","guild_infrastructure_pk",{primaryKey:["guild_id","structure_type"]});
  pgm.addConstraint("guild_infrastructure","guild_infrastructure_level_check",{check:"level >= 1 AND level <= 7"});
  pgm.createTable("guild_quests",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    guild_id:{type:"uuid",notNull:true,references:"guilds(id)",onDelete:"CASCADE"},
    operation_key:{type:"varchar(64)",notNull:true},
    title:{type:"varchar(128)",notNull:true},
    requirement_item:{type:"varchar(128)",notNull:true},
    target_quantity:{type:"bigint",notNull:true},
    progress_quantity:{type:"bigint",notNull:true,default:0},
    reward_xp:{type:"bigint",notNull:true},
    reward_gold:{type:"bigint",notNull:true},
    reward_badges:{type:"bigint",notNull:true,default:0},
    status:{type:"varchar(16)",notNull:true,default:"active"},
    starts_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    expires_at:{type:"timestamptz",notNull:true},
    completed_at:{type:"timestamptz",default:null}
  });
  pgm.addConstraint("guild_quests","guild_quests_target_check",{check:"target_quantity > 0 AND progress_quantity >= 0 AND reward_xp >= 0 AND reward_gold >= 0 AND reward_badges >= 0"});
  pgm.addConstraint("guild_quests","guild_quests_status_check",{check:"status IN ('active','completed','expired')"});
  pgm.createIndex("guild_quests",["guild_id","status","expires_at"]);
  pgm.createIndex("guild_quests",["guild_id","operation_key"],{unique:true});
};

export const down=(pgm)=>{
  pgm.dropTable("guild_quests");
  pgm.dropTable("guild_infrastructure");
  pgm.dropTable("guild_bank_transactions");
  pgm.dropTable("guild_bank_items");
  pgm.dropTable("guild_invitations");
  pgm.dropTable("guild_permissions");
  pgm.dropTable("guild_members");
  pgm.dropTable("guilds");
};
