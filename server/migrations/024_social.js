export const up=(pgm)=>{
  pgm.createTable("social_friendships",{
    user_a:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    user_b:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    status:{type:"varchar(16)",notNull:true,default:"pending"},
    requested_by:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("social_friendships","social_friendships_pk",{primaryKey:["user_a","user_b"]});
  pgm.addConstraint("social_friendships","social_friendships_order_check",{check:"user_a < user_b"});
  pgm.addConstraint("social_friendships","social_friendships_status_check",{check:"status IN ('pending','accepted')"});
  pgm.createIndex("social_friendships",["user_a","status"]);
  pgm.createIndex("social_friendships",["user_b","status"]);

  pgm.createTable("social_blocks",{
    blocker_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    blocked_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("social_blocks","social_blocks_pk",{primaryKey:["blocker_user_id","blocked_user_id"]});
  pgm.addConstraint("social_blocks","social_blocks_self_check",{check:"blocker_user_id <> blocked_user_id"});

  pgm.createTable("social_reports",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    reporter_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    target_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    reason:{type:"varchar(32)",notNull:true},
    details:{type:"varchar(512)",notNull:true,default:""},
    status:{type:"varchar(16)",notNull:true,default:"open"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    resolved_at:{type:"timestamptz"}
  });
  pgm.addConstraint("social_reports","social_reports_self_check",{check:"reporter_user_id <> target_user_id"});
  pgm.addConstraint("social_reports","social_reports_status_check",{check:"status IN ('open','reviewed','closed')"});
  pgm.createIndex("social_reports",["target_user_id","created_at"]);

  pgm.createTable("chat_messages",{
    id:{type:"bigserial",primaryKey:true},
    sender_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    recipient_user_id:{type:"uuid",references:"users(id)",onDelete:"SET NULL"},
    guild_id:{type:"uuid",references:"guilds(id)",onDelete:"CASCADE"},
    party_id:{type:"uuid"},
    channel:{type:"varchar(16)",notNull:true},
    region_id:{type:"integer"},
    body:{type:"varchar(512)",notNull:true},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("chat_messages","chat_messages_channel_check",{check:"channel IN ('local','region','party','guild','trade','global','system','whisper')"});
  pgm.addConstraint("chat_messages","chat_messages_body_check",{check:"length(trim(body)) BETWEEN 1 AND 512"});
  pgm.createIndex("chat_messages",["channel","created_at"]);
  pgm.createIndex("chat_messages",["sender_user_id","created_at"]);
  pgm.createIndex("chat_messages",["recipient_user_id","created_at"]);
  pgm.createIndex("chat_messages",["guild_id","created_at"]);
  pgm.createIndex("chat_messages",["party_id","created_at"]);
  pgm.createIndex("chat_messages",["region_id","created_at"]);

  pgm.createTable("parties",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    leader_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"RESTRICT"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.createTable("party_members",{
    party_id:{type:"uuid",notNull:true,references:"parties(id)",onDelete:"CASCADE"},
    user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    role:{type:"varchar(16)",notNull:true,default:"member"},
    joined_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("party_members","party_members_pk",{primaryKey:["party_id","user_id"]});
  pgm.addConstraint("party_members","party_members_role_check",{check:"role IN ('leader','member')"});
  pgm.createIndex("party_members",["user_id"],{unique:true});
  pgm.createTable("party_invitations",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    party_id:{type:"uuid",notNull:true,references:"parties(id)",onDelete:"CASCADE"},
    inviter_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    invitee_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"CASCADE"},
    status:{type:"varchar(16)",notNull:true,default:"pending"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    responded_at:{type:"timestamptz"}
  });
  pgm.addConstraint("party_invitations","party_invitations_status_check",{check:"status IN ('pending','accepted','declined','cancelled')"});
  pgm.createIndex("party_invitations",["invitee_user_id","status"]);
  pgm.createIndex("party_invitations",["party_id","invitee_user_id","status"]);

  pgm.createTable("auction_listings",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    seller_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"RESTRICT"},
    item_id:{type:"varchar(128)",notNull:true},
    category:{type:"varchar(32)",notNull:true,default:"other"},
    rarity:{type:"varchar(16)",notNull:true,default:"common"},
    item_level:{type:"integer",notNull:true,default:1},
    quantity:{type:"integer",notNull:true},
    remaining_quantity:{type:"integer",notNull:true},
    start_price:{type:"bigint",notNull:true},
    buy_now_price:{type:"bigint"},
    current_bid:{type:"bigint",notNull:true,default:0},
    highest_bidder_user_id:{type:"uuid",references:"users(id)",onDelete:"SET NULL"},
    seller_fee_bps:{type:"integer",notNull:true,default:500},
    status:{type:"varchar(16)",notNull:true,default:"active"},
    expires_at:{type:"timestamptz",notNull:true},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("auction_listings","auction_category_check",{check:"category IN ('resource','upgrade','defence','equipment','consumable','other')"});
  pgm.addConstraint("auction_listings","auction_rarity_check",{check:"rarity IN ('common','uncommon','rare','epic','legendary','mythic')"});
  pgm.addConstraint("auction_listings","auction_level_check",{check:"item_level BETWEEN 1 AND 100"});
  pgm.addConstraint("auction_listings","auction_quantity_check",{check:"quantity > 0 AND remaining_quantity >= 0 AND remaining_quantity <= quantity"});
  pgm.addConstraint("auction_listings","auction_prices_check",{check:"start_price > 0 AND current_bid >= 0 AND (buy_now_price IS NULL OR buy_now_price >= start_price)"});
  pgm.addConstraint("auction_listings","auction_fee_check",{check:"seller_fee_bps BETWEEN 0 AND 2000"});
  pgm.addConstraint("auction_listings","auction_status_check",{check:"status IN ('active','sold','expired','cancelled')"});
  pgm.createIndex("auction_listings",["status","expires_at"]);
  pgm.createIndex("auction_listings",["item_id","status","expires_at"]);
  pgm.createIndex("auction_listings",["category","rarity","item_level","status","expires_at"]);
  pgm.createIndex("auction_listings",["seller_user_id","status"]);

  pgm.createTable("auction_bids",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    listing_id:{type:"uuid",notNull:true,references:"auction_listings(id)",onDelete:"CASCADE"},
    bidder_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"RESTRICT"},
    amount:{type:"bigint",notNull:true},
    status:{type:"varchar(16)",notNull:true,default:"held"},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    settled_at:{type:"timestamptz"}
  });
  pgm.addConstraint("auction_bids","auction_bid_amount_check",{check:"amount > 0"});
  pgm.addConstraint("auction_bids","auction_bid_status_check",{check:"status IN ('held','refunded','won','settled')"});
  pgm.createIndex("auction_bids",["listing_id","created_at"]);
  pgm.createIndex("auction_bids",["bidder_user_id","status"]);

  pgm.createTable("auction_transactions",{
    id:{type:"uuid",primaryKey:true,default:pgm.func("gen_random_uuid()")},
    listing_id:{type:"uuid",notNull:true,references:"auction_listings(id)",onDelete:"RESTRICT"},
    buyer_user_id:{type:"uuid",references:"users(id)",onDelete:"SET NULL"},
    seller_user_id:{type:"uuid",notNull:true,references:"users(id)",onDelete:"RESTRICT"},
    item_id:{type:"varchar(128)",notNull:true},
    quantity:{type:"integer",notNull:true},
    gross_gold:{type:"bigint",notNull:true},
    seller_fee:{type:"bigint",notNull:true},
    net_gold:{type:"bigint",notNull:true},
    transaction_type:{type:"varchar(16)",notNull:true},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("auction_transactions","auction_transaction_type_check",{check:"transaction_type IN ('buy_now','bid_settlement','expiry_return','cancel_return')"});
  pgm.createIndex("auction_transactions",["seller_user_id","created_at"]);
  pgm.createIndex("auction_transactions",["buyer_user_id","created_at"]);
};

export const down=(pgm)=>{
  pgm.dropTable("auction_transactions");
  pgm.dropTable("auction_bids");
  pgm.dropTable("auction_listings");
  pgm.dropTable("party_invitations");
  pgm.dropTable("party_members");
  pgm.dropTable("parties");
  pgm.dropTable("chat_messages");
  pgm.dropTable("social_reports");
  pgm.dropTable("social_blocks");
  pgm.dropTable("social_friendships");
};