export const up=(pgm)=>{
  pgm.addColumn("resource_gather_requests",{
    transaction_id:{type:"uuid",default:pgm.func("gen_random_uuid()")}
  });
  pgm.sql("UPDATE resource_gather_requests SET transaction_id=gen_random_uuid() WHERE transaction_id IS NULL");
  pgm.alterColumn("resource_gather_requests","transaction_id",{notNull:true});
  pgm.addConstraint("resource_gather_requests","resource_gather_requests_transaction_id_unique",{unique:["transaction_id"]});
};

export const down=(pgm)=>{
  pgm.dropConstraint("resource_gather_requests","resource_gather_requests_transaction_id_unique");
  pgm.dropColumn("resource_gather_requests","transaction_id");
};
