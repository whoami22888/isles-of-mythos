export const up=(pgm)=>{
  pgm.addColumn("guild_bank_transactions",{
    request_key:{type:"varchar(128)"},
    fingerprint:{type:"text"},
    response:{type:"jsonb",notNull:true,default:pgm.func("'{}'::jsonb")}
  });
  pgm.createIndex("guild_bank_transactions","request_key",{unique:true,where:"request_key IS NOT NULL"});
};

export const down=(pgm)=>{
  pgm.dropIndex("guild_bank_transactions","request_key",{ifExists:true});
  pgm.dropColumns("guild_bank_transactions",["request_key","fingerprint","response"]);
};
