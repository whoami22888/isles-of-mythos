import type { Pool } from "pg";

export const BASE_GRID_MIN = -128;
export const BASE_GRID_MAX = 128;
export const MAX_BUILDING_LEVEL = 7;
export const BASE_STORAGE_CAPACITY = 1000;
export const STORAGE_CAPACITY_PER_LEVEL = 1000;
export const MAX_PRODUCTION_ELAPSED_MS = 24 * 60 * 60 * 1000;

export const BUILDING_TYPES = [
  "command_centre","storage","lumber_mill","steel_mill","forge","farm","fishing_dock",
  "breeding_pen","barracks","creature_stable","shipyard","watchtower","cannon_tower",
  "wall","gate","treasure_vault","guild_hall","research_laboratory","magic_observatory",
] as const;
export type BuildingType = typeof BUILDING_TYPES[number];

export const BASE_PERMISSIONS = ["build","storage","production","workers","manage"] as const;
export type BasePermission = typeof BASE_PERMISSIONS[number];

export const WORK_TASKS = ["repair","feed","collect","transport","process","store"] as const;
export type WorkTask = typeof WORK_TASKS[number];
export const WORKER_MODES = ["auto",...WORK_TASKS] as const;
export type WorkerMode = typeof WORKER_MODES[number];

export interface BaseBuilding {
  id: string;
  baseId: string;
  type: BuildingType;
  level: number;
  gridX: number;
  gridY: number;
  active: boolean;
}

export interface BaseWorker {
  creatureId: string;
  baseId: string;
  buildingId: string;
  task: WorkTask;
}

export interface BaseState {
  id: string;
  ownerUserId: string;
  name: string;
  x: number;
  y: number;
  buildings: BaseBuilding[];
  storage: Record<string, number>;
  workPriorities: string[];
  permissions: Record<string, BasePermission[]>;
  workers: BaseWorker[];
  productionProcessedAt: number;
}

interface BaseRow { id:string; owner_user_id:string; name:string; x:number; y:number; production_processed_at:Date|string; }
interface BuildingRow { id:string; base_id:string; type:BuildingType; level:number; grid_x:number; grid_y:number; active:boolean; }
interface StorageRow { resource_key:string; quantity:string; }
interface WorkerRow { creature_id:string; base_id:string; building_id:string; task:WorkerMode; }

export const BASE_BUILDING_DEFINITIONS: Record<BuildingType,{maxLevel:number; prerequisites:BuildingType[]}> = {
  command_centre:{maxLevel:7,prerequisites:[]}, storage:{maxLevel:7,prerequisites:["command_centre"]},
  lumber_mill:{maxLevel:7,prerequisites:["command_centre"]}, steel_mill:{maxLevel:7,prerequisites:["command_centre"]},
  forge:{maxLevel:7,prerequisites:["command_centre"]}, farm:{maxLevel:7,prerequisites:["command_centre"]},
  fishing_dock:{maxLevel:7,prerequisites:["command_centre"]}, breeding_pen:{maxLevel:7,prerequisites:["command_centre"]},
  barracks:{maxLevel:7,prerequisites:["command_centre"]}, creature_stable:{maxLevel:7,prerequisites:["command_centre"]},
  shipyard:{maxLevel:7,prerequisites:["command_centre"]}, watchtower:{maxLevel:7,prerequisites:["command_centre"]},
  cannon_tower:{maxLevel:7,prerequisites:["command_centre"]}, wall:{maxLevel:7,prerequisites:["command_centre"]},
  gate:{maxLevel:7,prerequisites:["command_centre"]}, treasure_vault:{maxLevel:7,prerequisites:["command_centre"]},
  guild_hall:{maxLevel:7,prerequisites:["command_centre"]}, research_laboratory:{maxLevel:7,prerequisites:["command_centre"]},
  magic_observatory:{maxLevel:7,prerequisites:["command_centre"]},
};

const PRODUCTION: Partial<Record<BuildingType,{output:string;ratePerMinute:number;input?:string;inputPerMinute:number}>> = {
  lumber_mill:{output:"wood",ratePerMinute:10,inputPerMinute:0},
  steel_mill:{output:"steel",ratePerMinute:5,input:"iron",inputPerMinute:10},
  farm:{output:"food",ratePerMinute:8,inputPerMinute:0},
  fishing_dock:{output:"fish",ratePerMinute:6,inputPerMinute:0},
};

function toQuantity(value:string|number):number {
  const n=typeof value==="number"?value:Number(value);
  if(!Number.isSafeInteger(n)||n<0)throw new Error("INVALID_STORAGE_QUANTITY");
  return n;
}
function rowToBuilding(r:BuildingRow):BaseBuilding {
  return {id:r.id,baseId:r.base_id,type:r.type,level:r.level,gridX:r.grid_x,gridY:r.grid_y,active:r.active};
}
function rowToWorker(r:WorkerRow):BaseWorker {
  return {creatureId:r.creature_id,baseId:r.base_id,buildingId:r.building_id,task:r.task};
}
export function storageCapacity(base:Pick<BaseState,"buildings">):number {
  return BASE_STORAGE_CAPACITY + base.buildings.filter(b=>b.active&&b.type==="storage").reduce((n,b)=>n+b.level*STORAGE_CAPACITY_PER_LEVEL,0);
}
export function calculateBuildingCost(type:BuildingType,level:number):Record<string,number>{
  if(!BASE_BUILDING_DEFINITIONS[type]||!Number.isSafeInteger(level)||level<1||level>MAX_BUILDING_LEVEL)throw new Error("INVALID_BUILDING_LEVEL");
  if(type==="command_centre"&&level===1)return {};
  const scale=level*level;
  return {wood:50*scale,stone:25*scale};
}
export function validateBuildingPlacement(base:Pick<BaseState,"buildings">,type:BuildingType,level:number,gridX:number,gridY:number):void{
  if(!BASE_BUILDING_DEFINITIONS[type])throw new Error("INVALID_BUILDING_TYPE");
  if(!Number.isSafeInteger(level)||level!==1)throw new Error("INVALID_BUILDING_LEVEL");
  if(!Number.isSafeInteger(gridX)||gridX<BASE_GRID_MIN||gridX>BASE_GRID_MAX||!Number.isSafeInteger(gridY)||gridY<BASE_GRID_MIN||gridY>BASE_GRID_MAX)throw new Error("INVALID_BUILDING_POSITION");
  if(base.buildings.some(b=>b.gridX===gridX&&b.gridY===gridY))throw new Error("BUILDING_POSITION_OCCUPIED");
  for(const prerequisite of BASE_BUILDING_DEFINITIONS[type].prerequisites)if(!base.buildings.some(b=>b.type===prerequisite&&b.active))throw new Error("BUILDING_PREREQUISITE_MISSING");
}
export function validateBuildingUpgrade(base:Pick<BaseState,"buildings">,buildingId:string):BaseBuilding{
  const building=base.buildings.find(b=>b.id===buildingId);
  if(!building)throw new Error("BUILDING_NOT_FOUND");
  if(building.level>=MAX_BUILDING_LEVEL)throw new Error("BUILDING_MAX_LEVEL");
  for(const prerequisite of BASE_BUILDING_DEFINITIONS[building.type].prerequisites)if(!base.buildings.some(b=>b.type===prerequisite&&b.active))throw new Error("BUILDING_PREREQUISITE_MISSING");
  return building;
}
export function productionFor(base:Pick<BaseState,"buildings"|"workers"|"storage">,elapsedMs:number):Record<string,number>{
  if(!Number.isFinite(elapsedMs)||elapsedMs<=0)return {};
  const elapsed=Math.min(elapsedMs,MAX_PRODUCTION_ELAPSED_MS)/60000;
  const deltas:Record<string,number>={};
  for(const building of base.buildings){
    if(!building.active)continue;
    const spec=PRODUCTION[building.type]; if(!spec)continue;
    const automaticTask=building.type==="lumber_mill"||building.type==="farm"||building.type==="fishing_dock"?"collect":building.type==="steel_mill"||building.type==="forge"?"process":null;
    const validTask=(worker:BaseWorker):boolean=>worker.task==="collect"&&automaticTask==="collect"||worker.task==="process"&&automaticTask==="process"||(worker.task==="auto"&&automaticTask!==null&&base.workPriorities.includes(automaticTask));
    const workerCount=base.workers.filter(w=>w.buildingId===building.id&&validTask(w)).length;
    if(workerCount===0)continue;
    const multiplier=building.level*workerCount;
    const output=Math.floor(spec.ratePerMinute*multiplier*elapsed);
    if(output>0)deltas[spec.output]=(deltas[spec.output]??0)+output;
    if(spec.input){
      const required=Math.floor(spec.inputPerMinute*multiplier*elapsed);
      if(required>0)deltas[spec.input]=(deltas[spec.input]??0)-required;
    }
  }
  return deltas;
}

export class BaseStore {
  private readonly active=new Map<string,BaseState>();
  private readonly operations=new Map<string,Promise<void>>();
  constructor(private readonly db:Pool){}
  private async runExclusive<T>(userId:string,operation:()=>Promise<T>):Promise<T>{
    const previous=this.operations.get(userId)??Promise.resolve();
    let release!:()=>void; const gate=new Promise<void>(resolve=>{release=resolve;});
    const queued=previous.catch(()=>undefined).then(()=>gate); this.operations.set(userId,queued);
    await previous.catch(()=>undefined);
    try{return await operation();}finally{release();if(this.operations.get(userId)===queued)this.operations.delete(userId);}
  }
  async load(userId:string):Promise<BaseState|null>{
    const cached=this.active.get(userId); if(cached)return cached;
    const base=await this.db.query<BaseRow>("SELECT id,owner_user_id,name,x,y,production_processed_at FROM player_bases WHERE owner_user_id=$1",[userId]);
    const row=base.rows[0]; if(!row)return null;
    const [buildings,storage,priorityRows,permissionRows,workerRows]=await Promise.all([
      this.db.query<BuildingRow>("SELECT id,base_id,type,level,grid_x,grid_y,active FROM base_buildings WHERE base_id=$1 ORDER BY grid_y,grid_x,id",[row.id]),
      this.db.query<StorageRow>("SELECT resource_key,quantity FROM base_storage WHERE base_id=$1",[row.id]),
      this.db.query<{priority:string}>("SELECT priority FROM base_work_priorities WHERE base_id=$1 ORDER BY priority_index",[row.id]),
      this.db.query<{user_id:string;permission:BasePermission}>("SELECT user_id,permission FROM base_permissions WHERE base_id=$1",[row.id]),
      this.db.query<WorkerRow>("SELECT creature_id,base_id,building_id,task FROM base_workers WHERE base_id=$1",[row.id]),
    ]);
    const permissions:Record<string,BasePermission[]>={};
    for(const p of permissionRows.rows)(permissions[p.user_id]??=[]).push(p.permission);
    const state:BaseState={
      id:row.id,ownerUserId:row.owner_user_id,name:row.name,x:row.x,y:row.y,
      buildings:buildings.rows.map(rowToBuilding),storage:Object.fromEntries(storage.rows.map(r=>[r.resource_key,toQuantity(r.quantity)])),
      workPriorities:priorityRows.rows.map(r=>r.priority),permissions,workers:workerRows.rows.map(rowToWorker),
      productionProcessedAt:new Date(row.production_processed_at).getTime(),
    };
    this.active.set(userId,state);
    await this.processProductionUnsafe(userId);
    return state;
  }
  get(userId:string):BaseState|null{return this.active.get(userId)??null;}
  async create(userId:string,name="Pirate Settlement",x=0,y=0):Promise<BaseState>{
    return this.runExclusive(userId,async()=>{
      if(await this.load(userId))throw new Error("BASE_ALREADY_EXISTS");
      if(!Number.isSafeInteger(x)||!Number.isSafeInteger(y))throw new Error("INVALID_BASE_COORDINATES");
      const client=await this.db.connect();
      try{
        await client.query("BEGIN");
        const inserted=await client.query<BaseRow>("INSERT INTO player_bases(owner_user_id,name,x,y) VALUES($1,$2,$3,$4) RETURNING id,owner_user_id,name,x,y,production_processed_at",[userId,name.trim().slice(0,64)||"Pirate Settlement",x,y]);
        const row=inserted.rows[0];
        await client.query("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'command_centre',1,0,0,true)",[row.id]);
        await client.query("INSERT INTO base_storage(base_id,resource_key,quantity) VALUES($1,'wood',500),($1,'stone',250),($1,'iron',100),($1,'food',100)",[row.id]);
        await client.query("INSERT INTO base_work_priorities(base_id,priority_index,priority) VALUES ($1,0,'repair'),($1,1,'feed'),($1,2,'collect'),($1,3,'transport'),($1,4,'process'),($1,5,'store')",[row.id]);
        await client.query("COMMIT");
        const state=await this.load(userId); if(!state)throw new Error("BASE_LOAD_FAILED"); return state;
      }catch(error){await client.query("ROLLBACK");if(typeof error==="object"&&error!==null&&"code" in error&&(error as {code?:unknown}).code==="23505")throw new Error("BASE_ALREADY_EXISTS",{cause:error});throw error;}finally{client.release();}
    });
  }
  async persistAndUnload(userId:string):Promise<void>{await this.runExclusive(userId,async()=>{await this.processProductionUnsafe(userId);this.active.delete(userId);});}
  async createBuilding(userId:string,type:BuildingType,level:number,gridX:number,gridY:number):Promise<BaseBuilding>{
    return this.runExclusive(userId,async()=>{
      const base=await this.load(userId); if(!base)throw new Error("BASE_NOT_FOUND");
      if(!BaseStore.can(userId,base,"build"))throw new Error("BASE_PERMISSION_DENIED");
      validateBuildingPlacement(base,type,level,gridX,gridY);
      const cost=calculateBuildingCost(type,level); this.ensureStorage(base,cost);
      const client=await this.db.connect();
      try{
        await client.query("BEGIN");
        await client.query("SELECT id FROM player_bases WHERE id=$1 FOR UPDATE",[base.id]);
        for(const [resource,quantity] of Object.entries(cost)){
          const locked=await client.query<{quantity:string}>("SELECT quantity FROM base_storage WHERE base_id=$1 AND resource_key=$2 FOR UPDATE",[base.id,resource]);
          if(Number(locked.rows[0]?.quantity??0)<quantity)throw new Error("INSUFFICIENT_STORAGE");
          await client.query("UPDATE base_storage SET quantity=quantity-$3,updated_at=CURRENT_TIMESTAMP WHERE base_id=$1 AND resource_key=$2",[base.id,resource,quantity]);
        }
        const result=await client.query<BuildingRow>("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,$2,$3,$4,$5,true) RETURNING id,base_id,type,level,grid_x,grid_y,active",[base.id,type,level,gridX,gridY]);
        await client.query("COMMIT");
        for(const [resource,quantity] of Object.entries(cost))base.storage[resource]=(base.storage[resource]??0)-quantity;
        const building=rowToBuilding(result.rows[0]); base.buildings.push(building); return building;
      }catch(error){await client.query("ROLLBACK");throw error;}finally{client.release();}
    });
  }
  async upgradeBuilding(userId:string,buildingId:string):Promise<BaseBuilding>{
    return this.runExclusive(userId,async()=>{
      const base=await this.load(userId); if(!base)throw new Error("BASE_NOT_FOUND");
      if(!BaseStore.can(userId,base,"build"))throw new Error("BASE_PERMISSION_DENIED");
      const building=validateBuildingUpgrade(base,buildingId); const nextLevel=building.level+1; const cost=calculateBuildingCost(building.type,nextLevel); this.ensureStorage(base,cost);
      const client=await this.db.connect();
      try{
        await client.query("BEGIN");
        await client.query("SELECT id FROM player_bases WHERE id=$1 FOR UPDATE",[base.id]);
        for(const [resource,quantity] of Object.entries(cost)){
          const locked=await client.query<{quantity:string}>("SELECT quantity FROM base_storage WHERE base_id=$1 AND resource_key=$2 FOR UPDATE",[base.id,resource]);
          if(Number(locked.rows[0]?.quantity??0)<quantity)throw new Error("INSUFFICIENT_STORAGE");
          await client.query("UPDATE base_storage SET quantity=quantity-$3,updated_at=CURRENT_TIMESTAMP WHERE base_id=$1 AND resource_key=$2",[base.id,resource,quantity]);
        }
        const result=await client.query<BuildingRow>("UPDATE base_buildings SET level=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND base_id=$3 RETURNING id,base_id,type,level,grid_x,grid_y,active",[buildingId,nextLevel,base.id]);
        if(!result.rows[0])throw new Error("BUILDING_NOT_FOUND");
        await client.query("COMMIT");
        for(const [resource,quantity] of Object.entries(cost))base.storage[resource]=(base.storage[resource]??0)-quantity;
        Object.assign(building,rowToBuilding(result.rows[0])); return building;
      }catch(error){await client.query("ROLLBACK");throw error;}finally{client.release();}
    });
  }
  async mutateStorage(userId:string,changes:Record<string,number>):Promise<Record<string,number>>{
    return this.runExclusive(userId,async()=>{
      const base=await this.load(userId); if(!base)throw new Error("BASE_NOT_FOUND");
      if(!BaseStore.can(userId,base,"storage"))throw new Error("BASE_PERMISSION_DENIED");
      this.validateStorageChanges(base,changes);
      const client=await this.db.connect();
      try{
        await client.query("BEGIN");
        const profile=await client.query<{inventory:Record<string,number>}>("SELECT inventory FROM player_profiles WHERE user_id=$1 FOR UPDATE",[userId]);
        if(!profile.rows[0])throw new Error("PLAYER_NOT_FOUND");
        const inventory={...(profile.rows[0].inventory??{})};
        const nextStorage={...base.storage};
        for(const [resource,delta] of Object.entries(changes)){
          if(delta===0)continue;
          const current=Number((await client.query<{quantity:string}>("SELECT quantity FROM base_storage WHERE base_id=$1 AND resource_key=$2 FOR UPDATE",[base.id,resource])).rows[0]?.quantity??0);
          if(delta>0){
            const owned=Number(inventory[resource]??0);
            if(!Number.isSafeInteger(owned)||owned<delta)throw new Error("INSUFFICIENT_INVENTORY");
            inventory[resource]=owned-delta;
          }else{
            if(current<Math.abs(delta))throw new Error("INSUFFICIENT_STORAGE");
            inventory[resource]=(Number(inventory[resource]??0))+Math.abs(delta);
          }
          const next=current+delta;
          if(next<0||!Number.isSafeInteger(next))throw new Error("INVALID_STORAGE_QUANTITY");
          await client.query("INSERT INTO base_storage(base_id,resource_key,quantity) VALUES($1,$2,$3) ON CONFLICT(base_id,resource_key) DO UPDATE SET quantity=EXCLUDED.quantity,updated_at=CURRENT_TIMESTAMP",[base.id,resource,next]);
          nextStorage[resource]=next;
        }
        if(Object.values(nextStorage).reduce((sum,n)=>sum+n,0)>storageCapacity(base))throw new Error("STORAGE_CAPACITY_EXCEEDED");
        await client.query("UPDATE player_profiles SET inventory=$2::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[userId,JSON.stringify(inventory)]);
        await client.query("COMMIT");
        base.storage=nextStorage; return {...base.storage};
      }catch(error){await client.query("ROLLBACK");throw error;}finally{client.release();}
    });
  }
  async setPermission(ownerUserId:string,targetUserId:string,permission:BasePermission,enabled:boolean):Promise<BaseState>{
    return this.runExclusive(ownerUserId,async()=>{
      const base=await this.load(ownerUserId); if(!base)throw new Error("BASE_NOT_FOUND");
      if(base.ownerUserId!==ownerUserId)throw new Error("BASE_PERMISSION_DENIED");
      if(targetUserId===ownerUserId)throw new Error("BASE_PERMISSION_DENIED");
      const client=await this.db.connect();
      try{
        await client.query("BEGIN");
        const target=await client.query("SELECT 1 FROM users WHERE id=$1",[targetUserId]);
        if(!target.rowCount)throw new Error("BASE_PERMISSION_DENIED");
        if(enabled)await client.query("INSERT INTO base_permissions(base_id,user_id,permission) VALUES($1,$2,$3) ON CONFLICT DO NOTHING",[base.id,targetUserId,permission]);
        else await client.query("DELETE FROM base_permissions WHERE base_id=$1 AND user_id=$2 AND permission=$3",[base.id,targetUserId,permission]);
        await client.query("COMMIT");
        const current=base.permissions[targetUserId]??[];
        base.permissions[targetUserId]=enabled?(current.includes(permission)?current:[...current,permission]):current.filter(p=>p!==permission);
        if(base.permissions[targetUserId].length===0)delete base.permissions[targetUserId];
        return base;
      }catch(error){await client.query("ROLLBACK");throw error;}finally{client.release();}
    });
  }
  async assignWorker(userId:string,creatureId:string,buildingId:string,task:WorkerMode):Promise<BaseWorker>{
    return this.runExclusive(userId,async()=>{
      const base=await this.load(userId); if(!base)throw new Error("BASE_NOT_FOUND");
      if(!BaseStore.can(userId,base,"workers"))throw new Error("BASE_PERMISSION_DENIED");
      if(!WORKER_MODES.includes(task))throw new Error("INVALID_WORK_TASK");
      const building=base.buildings.find(b=>b.id===buildingId&&b.active); if(!building)throw new Error("BUILDING_NOT_FOUND");
      const client=await this.db.connect();
      try{
        await client.query("BEGIN");
        const creature=await client.query<{tame_progress:number;party_slot:number|null;owner_user_id:string}>("SELECT tame_progress,party_slot,owner_user_id FROM player_creatures WHERE id=$1 FOR UPDATE",[creatureId]);
        const c=creature.rows[0]; if(!c||c.owner_user_id!==userId)throw new Error("CREATURE_NOT_FOUND");
        if(c.tame_progress<100)throw new Error("CREATURE_NOT_TAMED");
        if(c.party_slot!==null)throw new Error("CREATURE_IN_PARTY");
        await client.query("DELETE FROM base_workers WHERE creature_id=$1",[creatureId]);
        await client.query("INSERT INTO base_workers(creature_id,base_id,building_id,task) VALUES($1,$2,$3,$4)",[creatureId,base.id,buildingId,task]);
        await client.query("COMMIT");
        const worker={creatureId,baseId:base.id,buildingId,task}; base.workers=base.workers.filter(w=>w.creatureId!==creatureId); base.workers.push(worker); return worker;
      }catch(error){await client.query("ROLLBACK");throw error;}finally{client.release();}
    });
  }
  async setWorkPriorities(userId:string,priorities:string[]):Promise<BaseState>{
    return this.runExclusive(userId,async()=>{
      const base=await this.load(userId); if(!base)throw new Error("BASE_NOT_FOUND");
      if(!BaseStore.can(userId,base,"manage"))throw new Error("BASE_PERMISSION_DENIED");
      const normalized=priorities.filter(p=>WORK_TASKS.includes(p as WorkTask)).slice(0,WORK_TASKS.length);
      const client=await this.db.connect();
      try{
        await client.query("BEGIN"); await client.query("DELETE FROM base_work_priorities WHERE base_id=$1",[base.id]);
        for(const [index,priority] of normalized.entries())await client.query("INSERT INTO base_work_priorities(base_id,priority_index,priority) VALUES($1,$2,$3)",[base.id,index,priority]);
        await client.query("COMMIT"); base.workPriorities=normalized; return base;
      }catch(error){await client.query("ROLLBACK");throw error;}finally{client.release();}
    });
  }
  async processProduction(userId:string):Promise<BaseState|null>{return this.runExclusive(userId,async()=>{await this.load(userId);if(!this.active.has(userId))return null;await this.processProductionUnsafe(userId);return this.active.get(userId)??null;});}
  async processAll():Promise<void>{for(const userId of [...this.active.keys()])await this.processProduction(userId);}
  private async processProductionUnsafe(userId:string):Promise<void>{
    const base=this.active.get(userId); if(!base)return;
    const now=Date.now();
    const client=await this.db.connect();
    try{
      await client.query("BEGIN");
      const lockedBase=await client.query<{production_processed_at:Date|string}>("SELECT production_processed_at FROM player_bases WHERE id=$1 FOR UPDATE",[base.id]);
      const processedAt=lockedBase.rows[0]?new Date(lockedBase.rows[0].production_processed_at).getTime():now;
      const elapsed=Math.max(0,Math.min(now-processedAt,MAX_PRODUCTION_ELAPSED_MS));
      if(elapsed<1000){await client.query("COMMIT");return;}
      const [storageRows,buildingRows,workerRows]=await Promise.all([
        client.query<StorageRow>("SELECT resource_key,quantity FROM base_storage WHERE base_id=$1 FOR UPDATE",[base.id]),
        client.query<BuildingRow>("SELECT id,base_id,type,level,grid_x,grid_y,active FROM base_buildings WHERE base_id=$1",[base.id]),
        client.query<WorkerRow>("SELECT creature_id,base_id,building_id,task FROM base_workers WHERE base_id=$1",[base.id]),
      ]);
      const storage=Object.fromEntries(storageRows.rows.map(r=>[r.resource_key,toQuantity(r.quantity)]));
      const runtime={...base,storage,buildings:buildingRows.rows.map(rowToBuilding),workers:workerRows.rows.map(rowToWorker)};
      const deltas=productionFor(runtime,elapsed);
      const next={...storage};
      let valid=true;
      for(const [resource,delta] of Object.entries(deltas)){
        const value=(next[resource]??0)+delta;
        if(value<0||!Number.isSafeInteger(value)){valid=false;break;}
        next[resource]=value;
      }
      if(Object.values(next).reduce((sum,n)=>sum+n,0)>storageCapacity(runtime))valid=false;
      if(valid){
        for(const [resource,delta] of Object.entries(deltas)){
          if(delta===0)continue;
          await client.query("INSERT INTO base_storage(base_id,resource_key,quantity) VALUES($1,$2,$3) ON CONFLICT(base_id,resource_key) DO UPDATE SET quantity=EXCLUDED.quantity,updated_at=CURRENT_TIMESTAMP",[base.id,resource,next[resource]]);
        }
      }
      await client.query("UPDATE player_bases SET production_processed_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[base.id]);
      await client.query("COMMIT");
      base.storage=valid?next:storage; base.buildings=runtime.buildings; base.workers=runtime.workers; base.productionProcessedAt=now;
    }catch(error){await client.query("ROLLBACK");throw error;}
    finally{client.release();}
  }
  private ensureStorage(base:BaseState,cost:Record<string,number>):void{
    for(const [resource,quantity] of Object.entries(cost))if((base.storage[resource]??0)<quantity)throw new Error("INSUFFICIENT_STORAGE");
  }
  private validateStorageChanges(base:BaseState,changes:Record<string,number>):void{
    let total=Object.values(base.storage).reduce((s,n)=>s+n,0);
    for(const [resource,delta] of Object.entries(changes)){if(!Number.isSafeInteger(delta)||Math.abs(delta)>Number.MAX_SAFE_INTEGER)throw new Error("INVALID_STORAGE_QUANTITY");const next=(base.storage[resource]??0)+delta;if(next<0)throw new Error("INSUFFICIENT_STORAGE");total+=delta;}
    if(total>storageCapacity(base))throw new Error("STORAGE_CAPACITY_EXCEEDED");
  }
  static can(userId:string,base:BaseState,permission:BasePermission):boolean{return base.ownerUserId===userId||(base.permissions[userId]??[]).includes(permission);}
}
