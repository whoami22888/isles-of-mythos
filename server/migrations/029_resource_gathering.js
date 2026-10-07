export const up=(pgm)=>{
  pgm.createTable("world_resource_nodes",{
    node_id:{type:"varchar(128)",primaryKey:true},
    type:{type:"varchar(16)",notNull:true},
    x:{type:"integer",notNull:true},
    y:{type:"integer",notNull:true},
    depleted_until:{type:"timestamptz"},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("world_resource_nodes","world_resource_nodes_type_check",{check:"type IN ('wood','stone','herb')"});

  pgm.createTable("resource_gather_requests",{
    user_id:{type:"uuid",notNull:true,references:"player_profiles(user_id)",onDelete:"CASCADE"},
    request_id:{type:"varchar(64)",notNull:true},
    fingerprint:{type:"varchar(256)",notNull:true},
    node_id:{type:"varchar(128)",notNull:true},
    item_id:{type:"varchar(128)",notNull:true},
    quantity:{type:"integer",notNull:true},
    respawns_at:{type:"timestamptz",notNull:true},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")},
    updated_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.addConstraint("resource_gather_requests","resource_gather_requests_pk",{primaryKey:["user_id","request_id"]});
  pgm.addConstraint("resource_gather_requests","resource_gather_requests_quantity_check",{check:"quantity > 0"});
  pgm.createIndex("resource_gather_requests",["node_id","created_at"]);
};

export const down=(pgm)=>{
  pgm.dropTable("resource_gather_requests");
  pgm.dropTable("world_resource_nodes");
};
