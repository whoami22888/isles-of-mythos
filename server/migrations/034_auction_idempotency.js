export const up=(pgm)=>{
  pgm.addColumn("auction_transactions",{
    transaction_id:{type:"uuid",notNull:true,default:pgm.func("gen_random_uuid()")}
  });
  pgm.addConstraint("auction_transactions","auction_transactions_transaction_id_unique",{unique:["transaction_id"]});
  pgm.createTable("auction_requests",{
    request_key:{type:"varchar(128)",primaryKey:true},
    user_id:{type:"uuid",notNull:true,references:"player_profiles(user_id)",onDelete:"CASCADE"},
    fingerprint:{type:"varchar(512)",notNull:true},
    response:{type:"jsonb",notNull:true},
    created_at:{type:"timestamptz",notNull:true,default:pgm.func("CURRENT_TIMESTAMP")}
  });
  pgm.createIndex("auction_requests",["user_id","created_at"]);
};
export const down=(pgm)=>{
  pgm.dropTable("auction_requests");
  pgm.dropConstraint("auction_transactions","auction_transactions_transaction_id_unique");
  pgm.dropColumn("auction_transactions","transaction_id");
};
