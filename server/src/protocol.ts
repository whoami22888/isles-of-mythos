import type { PublicPlayerState } from "./player.js";
export interface ChunkCoordinate { x:number; y:number; }

export type ClientMessage =
  | { type:"ping" }
  | { type:"auth"; token:string }
  | { type:"subscribe_chunks"; requestId:string; chunks:ChunkCoordinate[] }
  | { type:"move"; dx:number; dy:number; dt:number }
  | { type:"select_hotbar"; slot:number }
  | { type:"attack"; requestId:string; targetId:string; facingX:number; facingY:number }
  | { type:"dodge"; facingX:number; facingY:number }
  | { type:"block"; active:boolean }
  | { type:"capture"; requestId:string; targetId:string }
  | { type:"tame"; requestId:string; creatureId:string }
  | { type:"set_creature_party"; requestId:string; creatureId:string; slot:number|null }
  | { type:"set_creature_ai"; requestId:string; creatureId:string; mode:"follow"|"assist"|"stay" }
  | { type:"create_base"; requestId:string; name:string; x:number; y:number }
  | { type:"build"; requestId:string; buildingType:string; level:number; gridX:number; gridY:number }
  | { type:"upgrade_building"; requestId:string; buildingId:string }
  | { type:"storage"; requestId:string; changes:Record<string,number> }
  | { type:"set_base_permission"; requestId:string; targetUserId:string; permission:string; enabled:boolean }
  | { type:"assign_worker"; requestId:string; creatureId:string; buildingId:string; task:string }
  | { type:"set_work_priorities"; requestId:string; priorities:string[] }
  | { type:"craft"; requestId:string; recipeId:string }
  | { type:"shop_purchase"; requestId:string; itemId:string; quantity:number }
  | { type:"trade"; requestId:string; toUserId:string; gold:string; items:Array<{itemId:string;quantity:number}> };

export type ServerMessage =
  | { type:"server_ready"; timestamp:number }
  | { type:"pong"; timestamp:number }
  | { type:"auth_ok"; userId:string }
  | { type:"player_state"; state:PublicPlayerState }
  | { type:"world_chunk"; requestId:string; chunk:unknown }
  | { type:"projectile_spawn"; projectileId:string; ownerUserId:string; targetId:string; x:number; y:number; vx:number; vy:number; expiresAt:number }
  | { type:"combat_result"; requestId:string; targetId:string; damage:number; critical:boolean; killed:boolean; targetHealth:number; status?:string; missed?:boolean }
  | { type:"creature_state"; requestId?:string; creature:unknown }
  | { type:"creature_party"; creatures:unknown[] }
  | { type:"base_state"; base:unknown }
  | { type:"building_state"; requestId:string; building:unknown }
  | { type:"craft_result"; requestId:string; recipeId:string; state:PublicPlayerState }
  | { type:"shop_purchase_result"; requestId:string; itemId:string; quantity:number; totalGold:string; state:PublicPlayerState }
  | { type:"trade_result"; requestId:string; from:unknown; to:unknown }
  | { type:"error"; code:
      | "INVALID_MESSAGE"|"UNSUPPORTED_MESSAGE"|"AUTH_REQUIRED"|"INVALID_TOKEN"|"COMBAT_COOLDOWN"|"OUT_OF_RANGE"|"NO_STAMINA"|"NO_AMMO"|"COMBAT_IN_PROGRESS"|"PLAYER_DEAD"|"PLAYER_STUNNED"|"RATE_LIMITED"
      | "CREATURE_TOO_HEALTHY"|"NO_CAPTURE_ORB"|"CREATURE_ALREADY_CAPTURED"|"CREATURE_NOT_FOUND"|"NO_CREATURE_FEED"|"CREATURE_NOT_TAMED"|"INVALID_PARTY_SLOT"
      | "BASE_ALREADY_EXISTS"|"BASE_NOT_FOUND"|"BASE_PERMISSION_DENIED"|"INVALID_BASE_COORDINATES"|"INVALID_BUILDING_TYPE"|"INVALID_BUILDING_LEVEL"
      | "INVALID_BUILDING_POSITION"|"BUILDING_POSITION_OCCUPIED"|"BUILDING_PREREQUISITE_MISSING"|"BUILDING_NOT_FOUND"|"BUILDING_MAX_LEVEL"
      | "INSUFFICIENT_STORAGE"|"STORAGE_CAPACITY_EXCEEDED"|"INVALID_STORAGE_QUANTITY"|"INSUFFICIENT_INVENTORY"|"PLAYER_NOT_FOUND"|"INVALID_WORK_TASK"|"CREATURE_IN_PARTY"
      | "RECIPE_NOT_FOUND"|"INVENTORY_LIMIT"|"SHOP_ITEM_NOT_FOUND"|"INVALID_PURCHASE_QUANTITY"|"INSUFFICIENT_GOLD"|"TRADE_REQUEST_CONFLICT"|"INVALID_TRADE_REQUEST"|"INVALID_TRADE_PARTICIPANTS"|"INVALID_TRADE_ITEMS"|"INVALID_TRADE_ITEM"|"INVALID_TRADE_QUANTITY"
      | "BUILD_FAILED"|"BASE_CREATE_FAILED"|"STORAGE_UPDATE_FAILED"|"UPGRADE_FAILED"|"PERMISSION_UPDATE_FAILED"|"WORKER_UPDATE_FAILED"|"PRIORITY_UPDATE_FAILED" };

function isSafeInteger(value:unknown):value is number{return typeof value==="number"&&Number.isSafeInteger(value);}
function isFiniteNumber(value:unknown):value is number{return typeof value==="number"&&Number.isFinite(value);}
function requestId(value:unknown):value is string{return typeof value==="string"&&value.length>0&&value.length<=64;}

export function parseClientMessage(raw:string):ClientMessage|null{
  try{
    const value:unknown=JSON.parse(raw);
    if(typeof value!=="object"||value===null||!("type" in value))return null;
    const type=(value as {type?:unknown}).type;
    if(type==="ping")return {type:"ping"};
    if(type==="auth"){const token=(value as {token?:unknown}).token;return typeof token==="string"&&token.length>0&&token.length<=4096?{type:"auth",token}:null;}
    if(type==="subscribe_chunks"){
      const id=(value as {requestId?:unknown}).requestId,chunks=(value as {chunks?:unknown}).chunks;
      if(!requestId(id)||!Array.isArray(chunks)||chunks.length===0||chunks.length>9)return null;
      const coordinates:ChunkCoordinate[]=[]; for(const chunk of chunks){if(typeof chunk!=="object"||chunk===null)return null;const x=(chunk as {x?:unknown}).x,y=(chunk as {y?:unknown}).y;if(!isSafeInteger(x)||!isSafeInteger(y)||Math.abs(x)>1_000_000||Math.abs(y)>1_000_000)return null;coordinates.push({x,y});}
      return {type:"subscribe_chunks",requestId:id,chunks:coordinates};
    }
    if(type==="move"){const dx=(value as {dx?:unknown}).dx,dy=(value as {dy?:unknown}).dy,dt=(value as {dt?:unknown}).dt;if(!isFiniteNumber(dx)||!isFiniteNumber(dy)||!isFiniteNumber(dt)||Math.abs(dx)>1||Math.abs(dy)>1||dt<0||dt>0.25)return null;return {type:"move",dx,dy,dt};}
    if(type==="select_hotbar"){const slot=(value as {slot?:unknown}).slot;return isSafeInteger(slot)&&slot>=0&&slot<8?{type:"select_hotbar",slot}:null;}
    if(type==="dodge"){const facingX=(value as {facingX?:unknown}).facingX,facingY=(value as {facingY?:unknown}).facingY;if(!isFiniteNumber(facingX)||!isFiniteNumber(facingY)||Math.abs(facingX)>1||Math.abs(facingY)>1||(facingX===0&&facingY===0))return null;return {type:"dodge",facingX,facingY};}
    if(type==="block"){const active=(value as {active?:unknown}).active;return typeof active==="boolean"?{type:"block",active}:null;}
    if(type==="capture"||type==="tame"||type==="set_creature_party"||type==="set_creature_ai"){
      const id=(value as {requestId?:unknown}).requestId;if(!requestId(id))return null;
      if(type==="capture"){const targetId=(value as {targetId?:unknown}).targetId;return typeof targetId==="string"&&targetId.length>0&&targetId.length<=128?{type:"capture",requestId:id,targetId}:null;}
      const creatureId=(value as {creatureId?:unknown}).creatureId;if(typeof creatureId!=="string"||creatureId.length===0||creatureId.length>64)return null;
      if(type==="tame")return {type:"tame",requestId:id,creatureId};
      if(type==="set_creature_party"){const slot=(value as {slot?:unknown}).slot;return slot===null||(isSafeInteger(slot)&&slot>=0&&slot<3)?{type:"set_creature_party",requestId:id,creatureId,slot}:null;}
      const mode=(value as {mode?:unknown}).mode;return mode==="follow"||mode==="assist"||mode==="stay"?{type:"set_creature_ai",requestId:id,creatureId,mode}:null;
    }
    if(type==="create_base"||type==="build"){
      const id=(value as {requestId?:unknown}).requestId;if(!requestId(id))return null;
      if(type==="create_base"){const name=(value as {name?:unknown}).name,x=(value as {x?:unknown}).x,y=(value as {y?:unknown}).y;return typeof name==="string"&&name.length<=64&&isSafeInteger(x)&&isSafeInteger(y)&&Math.abs(x)<=1_000_000&&Math.abs(y)<=1_000_000?{type:"create_base",requestId:id,name,x,y}:null;}
      const buildingType=(value as {buildingType?:unknown}).buildingType,level=(value as {level?:unknown}).level,gridX=(value as {gridX?:unknown}).gridX,gridY=(value as {gridY?:unknown}).gridY;return typeof buildingType==="string"&&buildingType.length>0&&buildingType.length<=32&&isSafeInteger(level)&&isSafeInteger(gridX)&&isSafeInteger(gridY)&&Math.abs(gridX)<=128&&Math.abs(gridY)<=128?{type:"build",requestId:id,buildingType,level,gridX,gridY}:null;
    }
    if(type==="upgrade_building"){const id=(value as {requestId?:unknown}).requestId,b=(value as {buildingId?:unknown}).buildingId;return requestId(id)&&typeof b==="string"&&b.length>0&&b.length<=64?{type:"upgrade_building",requestId:id,buildingId:b}:null;}
    if(type==="storage"){const id=(value as {requestId?:unknown}).requestId,changes=(value as {changes?:unknown}).changes;if(!requestId(id)||typeof changes!=="object"||changes===null||Array.isArray(changes))return null;const next:Record<string,number>={};const entries=Object.entries(changes);if(entries.length===0||entries.length>32)return null;for(const [key,delta] of entries){if(key.length===0||key.length>64||!isSafeInteger(delta)||Math.abs(delta)>1_000_000_000)return null;next[key]=delta;}return {type:"storage",requestId:id,changes:next};}
    if(type==="set_base_permission"){const id=(value as {requestId?:unknown}).requestId,targetUserId=(value as {targetUserId?:unknown}).targetUserId,permission=(value as {permission?:unknown}).permission,enabled=(value as {enabled?:unknown}).enabled;return requestId(id)&&typeof targetUserId==="string"&&targetUserId.length>0&&targetUserId.length<=64&&typeof permission==="string"&&permission.length>0&&permission.length<=32&&typeof enabled==="boolean"?{type:"set_base_permission",requestId:id,targetUserId,permission,enabled}:null;}
    if(type==="assign_worker"){const id=(value as {requestId?:unknown}).requestId,creatureId=(value as {creatureId?:unknown}).creatureId,buildingId=(value as {buildingId?:unknown}).buildingId,task=(value as {task?:unknown}).task;return requestId(id)&&typeof creatureId==="string"&&creatureId.length>0&&creatureId.length<=64&&typeof buildingId==="string"&&buildingId.length>0&&buildingId.length<=64&&typeof task==="string"&&task.length>0&&task.length<=32?{type:"assign_worker",requestId:id,creatureId,buildingId,task}:null;}
    if(type==="set_work_priorities"){const id=(value as {requestId?:unknown}).requestId,priorities=(value as {priorities?:unknown}).priorities;if(!requestId(id)||!Array.isArray(priorities)||priorities.length>6||priorities.some(p=>typeof p!=="string"||p.length===0||p.length>32))return null;return {type:"set_work_priorities",requestId:id,priorities:priorities as string[]};}
    if(type==="craft"){const id=(value as {requestId?:unknown}).requestId,recipeId=(value as {recipeId?:unknown}).recipeId;return requestId(id)&&typeof recipeId==="string"&&recipeId.length>0&&recipeId.length<=64?{type:"craft",requestId:id,recipeId}:null;}
    if(type==="shop_purchase"){const id=(value as {requestId?:unknown}).requestId,itemId=(value as {itemId?:unknown}).itemId,quantity=(value as {quantity?:unknown}).quantity;return requestId(id)&&typeof itemId==="string"&&itemId.length>0&&itemId.length<=64&&isSafeInteger(quantity)&&quantity>=1&&quantity<=100?{type:"shop_purchase",requestId:id,itemId,quantity}:null;}
    if(type==="trade"){
      const id=(value as {requestId?:unknown}).requestId,toUserId=(value as {toUserId?:unknown}).toUserId,gold=(value as {gold?:unknown}).gold,items=(value as {items?:unknown}).items;
      if(!requestId(id)||typeof toUserId!=="string"||toUserId.length===0||toUserId.length>64||typeof gold!=="string"||gold.length===0||gold.length>32||!Array.isArray(items)||items.length>32)return null;
      const normalized:Array<{itemId:string;quantity:number}>=[];
      for(const item of items){if(typeof item!=="object"||item===null||Array.isArray(item))return null;const itemId=(item as {itemId?:unknown}).itemId,quantity=(item as {quantity?:unknown}).quantity;if(typeof itemId!=="string"||itemId.length===0||itemId.length>128||!isSafeInteger(quantity)||quantity<1||quantity>1_000_000)return null;normalized.push({itemId,quantity});}
      return {type:"trade",requestId:id,toUserId,gold,items:normalized};
    }
    if(type==="attack"){
      const id=(value as {requestId?:unknown}).requestId,targetId=(value as {targetId?:unknown}).targetId,facingX=(value as {facingX?:unknown}).facingX,facingY=(value as {facingY?:unknown}).facingY;
      if(!requestId(id)||typeof targetId!=="string"||targetId.length===0||targetId.length>128||!isFiniteNumber(facingX)||!isFiniteNumber(facingY)||Math.abs(facingX)>1||Math.abs(facingY)>1||(facingX===0&&facingY===0))return null;
      return {type:"attack",requestId:id,targetId,facingX,facingY};
    }
  }catch{return null;}
  return null;
}
