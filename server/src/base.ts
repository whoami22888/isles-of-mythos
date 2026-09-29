import type { Pool } from "pg";

export const BASE_GRID_MIN = -128;
export const BASE_GRID_MAX = 128;
export const MAX_BUILDING_LEVEL = 7;

export const BUILDING_TYPES = [
  "command_centre","storage","lumber_mill","steel_mill","forge","farm","fishing_dock",
  "breeding_pen","barracks","creature_stable","shipyard","watchtower","cannon_tower",
  "wall","gate","treasure_vault","guild_hall","research_laboratory","magic_observatory",
] as const;
export type BuildingType = typeof BUILDING_TYPES[number];

export const BASE_PERMISSIONS = ["build","storage","production","workers","manage"] as const;
export type BasePermission = typeof BASE_PERMISSIONS[number];

export interface BaseBuilding {
  id: string;
  baseId: string;
  type: BuildingType;
  level: number;
  gridX: number;
  gridY: number;
  active: boolean;
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
}

interface BaseRow {
  id:string; owner_user_id:string; name:string; x:number; y:number;
}
interface BuildingRow {
  id:string; base_id:string; type:BuildingType; level:number; grid_x:number; grid_y:number; active:boolean;
}
interface StorageRow { resource_key:string; quantity:string; }

export const BASE_BUILDING_DEFINITIONS: Record<BuildingType,{maxLevel:number; prerequisites:BuildingType[]}> = {
  command_centre:{maxLevel:7,prerequisites:[]},
  storage:{maxLevel:7,prerequisites:["command_centre"]},
  lumber_mill:{maxLevel:7,prerequisites:["command_centre"]},
  steel_mill:{maxLevel:7,prerequisites:["command_centre"]},
  forge:{maxLevel:7,prerequisites:["command_centre"]},
  farm:{maxLevel:7,prerequisites:["command_centre"]},
  fishing_dock:{maxLevel:7,prerequisites:["command_centre"]},
  breeding_pen:{maxLevel:7,prerequisites:["command_centre"]},
  barracks:{maxLevel:7,prerequisites:["command_centre"]},
  creature_stable:{maxLevel:7,prerequisites:["command_centre"]},
  shipyard:{maxLevel:7,prerequisites:["command_centre"]},
  watchtower:{maxLevel:7,prerequisites:["command_centre"]},
  cannon_tower:{maxLevel:7,prerequisites:["command_centre"]},
  wall:{maxLevel:7,prerequisites:["command_centre"]},
  gate:{maxLevel:7,prerequisites:["command_centre"]},
  treasure_vault:{maxLevel:7,prerequisites:["command_centre"]},
  guild_hall:{maxLevel:7,prerequisites:["command_centre"]},
  research_laboratory:{maxLevel:7,prerequisites:["command_centre"]},
  magic_observatory:{maxLevel:7,prerequisites:["command_centre"]},
};

function toQuantity(value:string|number):number {
  const n=typeof value==="number"?value:Number(value);
  if(!Number.isSafeInteger(n)||n<0)throw new Error("INVALID_STORAGE_QUANTITY");
  return n;
}

function rowToBuilding(r:BuildingRow):BaseBuilding {
  return {id:r.id,baseId:r.base_id,type:r.type,level:r.level,gridX:r.grid_x,gridY:r.grid_y,active:r.active};
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
  for(const prerequisite of BASE_BUILDING_DEFINITIONS[type].prerequisites){
    if(!base.buildings.some(b=>b.type===prerequisite&&b.active))throw new Error("BUILDING_PREREQUISITE_MISSING");
  }
}
export function validateBuildingUpgrade(base:Pick<BaseState,"buildings">,buildingId:string):BaseBuilding{
  const building=base.buildings.find(b=>b.id===buildingId);
  if(!building)throw new Error("BUILDING_NOT_FOUND");
  if(building.level>=MAX_BUILDING_LEVEL)throw new Error("BUILDING_MAX_LEVEL");
  return building;
}

export class BaseStore {
  private readonly active=new Map<string,BaseState>();
  private readonly operations=new Map<string,Promise<void>>();

  constructor(private readonly db:Pool){}

  private async runExclusive<T>(userId:string,operation:()=>Promise<T>):Promise<T>{
    const previous=this.operations.get(userId)??Promise.resolve();
    let release!:()=>void;
    const gate=new Promise<void>(resolve=>{release=resolve;});
    const queued=previous.catch(()=>undefined).then(()=>gate);
    this.operations.set(userId,queued);
    await previous.catch(()=>undefined);
    try{return await operation();}
    finally{
      release();
      if(this.operations.get(userId)===queued)this.operations.delete(userId);
    }
  }

  async load(userId:string):Promise<BaseState|null>{
    const cached=this.active.get(userId);
    if(cached)return cached;
    const base=await this.db.query<BaseRow>(
      "SELECT id,owner_user_id,name,x,y FROM player_bases WHERE owner_user_id=$1",
      [userId],
    );
    const row=base.rows[0];
    if(!row)return null;
    const [buildings,storage,priorityRows,permissionRows]=await Promise.all([
      this.db.query<BuildingRow>("SELECT id,base_id,type,level,grid_x,grid_y,active FROM base_buildings WHERE base_id=$1 ORDER BY grid_y,grid_x,id",[row.id]),
      this.db.query<StorageRow>("SELECT resource_key,quantity FROM base_storage WHERE base_id=$1",[row.id]),
      this.db.query<{priority:string}>("SELECT priority FROM base_work_priorities WHERE base_id=$1 ORDER BY priority_index",[row.id]),
      this.db.query<{user_id:string;permission:BasePermission}>("SELECT user_id,permission FROM base_permissions WHERE base_id=$1",[row.id]),
    ]);
    const permissions:Record<string,BasePermission[]>={};
    for(const p of permissionRows.rows)(permissions[p.user_id]??=[]).push(p.permission);
    const state:BaseState={
      id:row.id,ownerUserId:row.owner_user_id,name:row.name,x:row.x,y:row.y,
      buildings:buildings.rows.map(rowToBuilding),
      storage:Object.fromEntries(storage.rows.map(r=>[r.resource_key,toQuantity(r.quantity)])),
      workPriorities:priorityRows.rows.map(r=>r.priority),
      permissions,
    };
    this.active.set(userId,state);
    return state;
  }

  get(userId:string):BaseState|null{return this.active.get(userId)??null;}

  async create(userId:string,name="Pirate Settlement",x=0,y=0):Promise<BaseState>{
    return this.runExclusive(userId,async()=>{
      const existing=await this.load(userId);
      if(existing)throw new Error("BASE_ALREADY_EXISTS");
      if(!Number.isSafeInteger(x)||!Number.isSafeInteger(y))throw new Error("INVALID_BASE_COORDINATES");
      const client=await this.db.connect();
      try{
        await client.query("BEGIN");
        const inserted=await client.query<BaseRow>(
          "INSERT INTO player_bases(owner_user_id,name,x,y) VALUES($1,$2,$3,$4) RETURNING id,owner_user_id,name,x,y",
          [userId,name.trim().slice(0,64)||"Pirate Settlement",x,y],
        );
        const row=inserted.rows[0];
        await client.query(
          "INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'command_centre',1,0,0,true)",
          [row.id],
        );
        await client.query(
          "INSERT INTO base_work_priorities(base_id,priority_index,priority) VALUES ($1,0,'repair'),($1,1,'feed'),($1,2,'collect'),($1,3,'transport'),($1,4,'process'),($1,5,'store')",
          [row.id],
        );
        await client.query("COMMIT");
        const state=await this.load(userId);
        if(!state)throw new Error("BASE_LOAD_FAILED");
        return state;
      }catch(error){await client.query("ROLLBACK");throw error;}finally{client.release();}
    });
  }

  async persistAndUnload(userId:string):Promise<void>{
    await this.runExclusive(userId,async()=>{this.active.delete(userId);});
  }

  async createBuilding(userId:string,type:BuildingType,level:number,gridX:number,gridY:number):Promise<BaseBuilding>{\n    return this.runExclusive(userId,async()=>{\n      const base=await this.load(userId);\n      if(!base)throw new Error("BASE_NOT_FOUND");\n      if(!BaseStore.can(userId,base,"build"))throw new Error("BASE_PERMISSION_DENIED");\n      validateBuildingPlacement(base,type,level,gridX,gridY);\n      const client=await this.db.connect();\n      try{\n        await client.query("BEGIN");\n        const result=await client.query<BuildingRow>("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,$2,$3,$4,$5,true) RETURNING id,base_id,type,level,grid_x,grid_y,active",[base.id,type,level,gridX,gridY]);\n        await client.query("COMMIT");\n        const building=rowToBuilding(result.rows[0]);\n        base.buildings.push(building);\n        return building;\n      }catch(error){await client.query("ROLLBACK");throw error;}finally{client.release();}\n    });\n  }\n\n  static can(userId:string,base:BaseState,permission:BasePermission):boolean{
    return base.ownerUserId===userId || (base.permissions[userId]??[]).includes(permission);
  }
}
