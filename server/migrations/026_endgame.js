import { randomUUID } from "node:crypto";

export async function up(pgm) {
  pgm.createTable("realm_wars", {
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    attacker_realm_id:{type:"uuid",notNull:true,references:"realms(id)"},
    defender_realm_id:{type:"uuid",notNull:true,references:"realms(id)"},
    target_territory_id:{type:"uuid",notNull:true,references:"territories(id)"},
    status:{type:"text",notNull:true,default:"active"},
    phase:{type:"text",notNull:true,default:"mobilization"},
    attacker_score:{type:"bigint",notNull:true,default:0},
    defender_score:{type:"bigint",notNull:true,default:0},
    started_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    ends_at:{type:"timestamptz",notNull:true},
    winner_realm_id:{type:"uuid",references:"realms(id)"},
    state:{type:"jsonb",notNull:true,default:"{}"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("realm_wars","realm_wars_distinct_sides",{check:"attacker_realm_id <> defender_realm_id"});
  pgm.addConstraint("realm_wars_status_check",{check:"status IN ('active','resolved','cancelled')"});
  pgm.addConstraint("realm_wars_phase_check",{check:"phase IN ('mobilization','assault','resolution')"});
  pgm.addConstraint("realm_wars_score_check",{check:"attacker_score >= 0 AND defender_score >= 0"});
  pgm.createIndex("realm_wars",["status","ends_at"]);
  pgm.createIndex("realm_wars",["target_territory_id","status"]);

  pgm.createTable("realm_war_participants", {
    war_id:{type:"uuid",notNull:true,references:"realm_wars(id)",onDelete:"CASCADE"},
    guild_id:{type:"uuid",notNull:true,references:"guilds(id)",onDelete:"CASCADE"},
    realm_id:{type:"uuid",notNull:true,references:"realms(id)"},
    contribution:{type:"bigint",notNull:true,default:0},
    actions:{type:"integer",notNull:true,default:0},
    joined_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    primaryKey:["war_id","guild_id"]
  });
  pgm.addConstraint("realm_war_participants","realm_war_participants_contribution_check",{check:"contribution >= 0 AND actions >= 0"});
  pgm.createIndex("realm_war_participants",["guild_id","war_id"]);

  pgm.createTable("guild_battles", {
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    attacker_guild_id:{type:"uuid",notNull:true,references:"guilds(id)"},
    defender_guild_id:{type:"uuid",notNull:true,references:"guilds(id)"},
    target_territory_id:{type:"uuid",notNull:true,references:"territories(id)"},
    status:{type:"text",notNull:true,default:"active"},
    phase:{type:"text",notNull:true,default:"deployment"},
    attacker_score:{type:"bigint",notNull:true,default:0},
    defender_score:{type:"bigint",notNull:true,default:0},
    started_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    ends_at:{type:"timestamptz",notNull:true},
    winner_guild_id:{type:"uuid",references:"guilds(id)"},
    state:{type:"jsonb",notNull:true,default:"{}"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("guild_battles","guild_battles_distinct_sides",{check:"attacker_guild_id <> defender_guild_id"});
  pgm.addConstraint("guild_battles_status_check",{check:"status IN ('active','resolved','cancelled')"});
  pgm.addConstraint("guild_battles_phase_check",{check:"phase IN ('deployment','engagement','resolution')"});
  pgm.addConstraint("guild_battles_score_check",{check:"attacker_score >= 0 AND defender_score >= 0"});
  pgm.createIndex("guild_battles",["status","ends_at"]);

  pgm.createTable("guild_battle_armies", {
    battle_id:{type:"uuid",notNull:true,references:"guild_battles(id)",onDelete:"CASCADE"},
    army_id:{type:"uuid",notNull:true,references:"armies(id)",onDelete:"CASCADE"},
    guild_id:{type:"uuid",notNull:true,references:"guilds(id)"},
    side:{type:"text",notNull:true},
    contribution:{type:"bigint",notNull:true,default:0},
    actions:{type:"integer",notNull:true,default:0},
    joined_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    primaryKey:["battle_id","army_id"]
  });
  pgm.addConstraint("guild_battle_armies","guild_battle_armies_side_check",{check:"side IN ('attacker','defender')"});
  pgm.addConstraint("guild_battle_armies","guild_battle_armies_contribution_check",{check:"contribution >= 0 AND actions >= 0"});
  pgm.createIndex("guild_battle_armies",["battle_id","side"]);

  pgm.createTable("endgame_creature_templates", {
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    species:{type:"text",notNull:true,unique:true},
    rarity:{type:"text",notNull:true,default:"ancient"},
    level:{type:"integer",notNull:true},
    element:{type:"text",notNull:true},
    max_health:{type:"integer",notNull:true},
    attack:{type:"integer",notNull:true},
    defense:{type:"integer",notNull:true},
    ability_ids:{type:"jsonb",notNull:true,default:"[]"},
    mythic_content_key:{type:"text",notNull:true},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("endgame_creature_templates","endgame_creature_level_check",{check:"level >= 50 AND level <= 100"});
  pgm.createTable("endgame_creatures", {
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    template_id:{type:"uuid",notNull:true,references:"endgame_creature_templates(id)"},
    x:{type:"integer",notNull:true},
    y:{type:"integer",notNull:true},
    health:{type:"integer",notNull:true},
    status:{type:"text",notNull:true,default:"wild"},
    defeated_by:{type:"uuid",references:"users(id)"},
    defeated_at:{type:"timestamptz"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("endgame_creatures","endgame_creature_health_check",{check:"health >= 0"});
  pgm.addConstraint("endgame_creatures","endgame_creature_status_check",{check:"status IN ('wild','defeated')"});
  pgm.createIndex("endgame_creatures",["status","template_id"]);

  pgm.createTable("mythic_content", {
    content_key:{type:"text",primaryKey:true},
    title:{type:"text",notNull:true},
    tier:{type:"text",notNull:true},
    unlock_level:{type:"integer",notNull:true},
    description:{type:"text",notNull:true},
    reward:{type:"jsonb",notNull:true,default:"{}"},
    active:{type:"boolean",notNull:true,default:true}
  });
  pgm.addConstraint("mythic_content","mythic_content_tier_check",{check:"tier IN ('mythic','ancient','celestial')"});
  pgm.createIndex("mythic_content",["active","unlock_level"]);

  pgm.sql(`INSERT INTO mythic_content(content_key,title,tier,unlock_level,description,reward) VALUES
    ('realm_war','Realm War','mythic',50,'Persistent realm-scale warfare over strategic territories.', '{"triumphBadges":"25"}'),
    ('guild_legion','Grand Guild Legion','mythic',55,'Large guild battles with multiple server-authoritative armies.', '{"gold":"50000"}'),
    ('ancient_beasts','Ancient Beasts','ancient',50,'High-level persistent creatures with endgame statistics.', '{"gold":"25000"}'),
    ('mythic_vault','Mythic Vault','celestial',60,'Mythic endgame rewards unlocked by realm and guild achievements.', '{"triumphBadges":"50"}')
    ON CONFLICT(content_key) DO NOTHING`);
  pgm.sql(`INSERT INTO endgame_creature_templates(species,rarity,level,element,max_health,attack,defense,ability_ids,mythic_content_key) VALUES
    ('ancient_sea_dragon','ancient',75,'fire',18000,420,300,'["dragon_breath","tidal_roar"]','ancient_beasts'),
    ('abyssal_behemoth','ancient',80,'shadow',22000,460,380,'["crushing_blow","abyssal_roar"]','ancient_beasts'),
    ('celestial_leviathan','celestial',90,'water',30000,560,450,'["tidal_cataclysm","leviathan_guard"]','mythic_vault'),
    ('mythic_sky_dragon','mythic',100,'arcane',40000,700,520,'["arcane_breath","skyfall"]','mythic_vault')
    ON CONFLICT(species) DO NOTHING`);
}

export async function down(pgm) {
  pgm.dropTable("mythic_content");
  pgm.dropTable("endgame_creatures");
  pgm.dropTable("endgame_creature_templates");
  pgm.dropTable("guild_battle_armies");
  pgm.dropTable("guild_battles");
  pgm.dropTable("realm_war_participants");
  pgm.dropTable("realm_wars");
}