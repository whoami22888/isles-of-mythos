export interface ChunkCoordinate {
  x: number;
  y: number;
}

export type ClientMessage =
  | { type: "ping" }
  | { type: "auth"; token: string }
  | { type: "subscribe_chunks"; requestId: string; chunks: ChunkCoordinate[] }
  | { type: "move"; dx: number; dy: number; dt: number }
  | { type: "select_hotbar"; slot: number }
  | { type: "attack"; requestId: string; targetId: string; facingX: number; facingY: number }
  | { type: "dodge"; facingX: number; facingY: number }
  | { type: "block"; active: boolean }
  | { type: "capture"; requestId: string; targetId: string }
  | { type: "tame"; requestId: string; creatureId: string }
  | { type: "set_creature_party"; requestId: string; creatureId: string; slot: number | null }
  | { type: "set_creature_ai"; requestId: string; creatureId: string; mode: "follow" | "assist" | "stay" }\n  | { type: "create_base"; requestId: string; name: string; x: number; y: number }\n  | { type: "build"; requestId: string; buildingType: string; level: number; gridX: number; gridY: number };

export type ServerMessage =
  | { type: "server_ready"; timestamp: number }
  | { type: "pong"; timestamp: number }
  | { type: "auth_ok"; userId: string }
  | { type: "player_state"; state: unknown }
  | { type: "world_chunk"; requestId: string; chunk: unknown }
  | { type: "projectile_spawn"; projectileId: string; ownerUserId: string; targetId: string; x: number; y: number; vx: number; vy: number; expiresAt: number }
  | { type: "combat_result"; requestId: string; targetId: string; damage: number; critical: boolean; killed: boolean; targetHealth: number; status?: string; missed?: boolean }
  | { type: "creature_state"; requestId?: string; creature: unknown }
  | { type: "creature_party"; creatures: unknown[] }\n  | { type: "base_state"; base: unknown }\n  | { type: "building_state"; requestId: string; building: unknown }
  | {
      type: "error";
      code:
        | "INVALID_MESSAGE"
        | "UNSUPPORTED_MESSAGE"
        | "AUTH_REQUIRED"
        | "INVALID_TOKEN"
        | "COMBAT_COOLDOWN"
        | "OUT_OF_RANGE"
        | "NO_STAMINA"
        | "NO_AMMO"
        | "COMBAT_IN_PROGRESS"
        | "PLAYER_DEAD"
        | "PLAYER_STUNNED"
        | "RATE_LIMITED"
        | "CREATURE_TOO_HEALTHY"
        | "NO_CAPTURE_ORB"
        | "CREATURE_ALREADY_CAPTURED"
        | "CREATURE_NOT_FOUND"
        | "NO_CREATURE_FEED"
        | "CREATURE_NOT_TAMED"
        | "INVALID_PARTY_SLOT"\n        | "BASE_ALREADY_EXISTS"\n        | "BASE_NOT_FOUND"\n        | "BASE_PERMISSION_DENIED"\n        | "INVALID_BASE_COORDINATES"\n        | "INVALID_BUILDING_TYPE"\n        | "INVALID_BUILDING_LEVEL"\n        | "INVALID_BUILDING_POSITION"\n        | "BUILDING_POSITION_OCCUPIED"\n        | "BUILDING_PREREQUISITE_MISSING"\n        | "BUILD_FAILED"\n        | "BASE_CREATE_FAILED";
    };

function isSafeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

export function parseClientMessage(raw: string): ClientMessage | null {
  try {
    const value: unknown = JSON.parse(raw);
    if (typeof value !== "object" || value === null || !("type" in value)) return null;
    const type = (value as { type?: unknown }).type;

    if (type === "ping") return { type: "ping" };

    if (type === "auth") {
      const token = (value as { token?: unknown }).token;
      return typeof token === "string" && token.length > 0 && token.length <= 4096
        ? { type: "auth", token }
        : null;
    }

    if (type === "subscribe_chunks") {
      const requestId = (value as { requestId?: unknown }).requestId;
      const chunks = (value as { chunks?: unknown }).chunks;
      if (
        typeof requestId !== "string" ||
        requestId.length === 0 ||
        requestId.length > 64 ||
        !Array.isArray(chunks) ||
        chunks.length === 0 ||
        chunks.length > 9
      ) return null;

      const coordinates: ChunkCoordinate[] = [];
      for (const chunk of chunks) {
        if (typeof chunk !== "object" || chunk === null || !("x" in chunk) || !("y" in chunk)) return null;
        const x = (chunk as { x?: unknown }).x;
        const y = (chunk as { y?: unknown }).y;
        if (!isSafeInteger(x) || !isSafeInteger(y) || Math.abs(x) > 1_000_000 || Math.abs(y) > 1_000_000) return null;
        coordinates.push({ x, y });
      }
      return { type: "subscribe_chunks", requestId, chunks: coordinates };
    }

    if (type === "move") {
      const dx = (value as { dx?: unknown }).dx;
      const dy = (value as { dy?: unknown }).dy;
      const dt = (value as { dt?: unknown }).dt;
      if (!isFiniteNumber(dx) || !isFiniteNumber(dy) || !isFiniteNumber(dt) ||
          Math.abs(dx) > 1 || Math.abs(dy) > 1 || dt < 0 || dt > 0.25) return null;
      return { type: "move", dx, dy, dt };
    }

    if (type === "select_hotbar") {
      const slot = (value as { slot?: unknown }).slot;
      return isSafeInteger(slot) && slot >= 0 && slot < 8 ? { type: "select_hotbar", slot } : null;
    }

    if (type === "dodge") {
      const facingX = (value as { facingX?: unknown }).facingX;
      const facingY = (value as { facingY?: unknown }).facingY;
      if (!isFiniteNumber(facingX) || !isFiniteNumber(facingY) ||
          Math.abs(facingX) > 1 || Math.abs(facingY) > 1 ||
          (facingX === 0 && facingY === 0)) return null;
      return { type: "dodge", facingX, facingY };
    }

    if (type === "capture" || type === "tame" || type === "set_creature_party" || type === "set_creature_ai") {
      const requestId=(value as {requestId?:unknown}).requestId;
      if(typeof requestId!=="string"||requestId.length===0||requestId.length>64)return null;
      if(type==="capture"){const targetId=(value as {targetId?:unknown}).targetId;return typeof targetId==="string"&&targetId.length<=128?{type:"capture",requestId,targetId}:null;}
      if(type==="tame"){const creatureId=(value as {creatureId?:unknown}).creatureId;return typeof creatureId==="string"&&creatureId.length<=64?{type:"tame",requestId,creatureId}:null;}
      const creatureId=(value as {creatureId?:unknown}).creatureId;
      if(typeof creatureId!=="string"||creatureId.length===0||creatureId.length>64)return null;
      if(type==="set_creature_party"){const slot=(value as {slot?:unknown}).slot;return (slot===null||(isSafeInteger(slot)&&slot>=0&&slot<3))?{type:"set_creature_party",requestId,creatureId,slot}:null;}
      const mode=(value as {mode?:unknown}).mode;return mode==="follow"||mode==="assist"||mode==="stay"?{type:"set_creature_ai",requestId,creatureId,mode}:null;
    }

    if (type === "create_base" || type === "build") {\n      const requestId=(value as {requestId?:unknown}).requestId;\n      if(typeof requestId!=="string"||requestId.length===0||requestId.length>64)return null;\n      if(type==="create_base"){const name=(value as {name?:unknown}).name; const x=(value as {x?:unknown}).x; const y=(value as {y?:unknown}).y; return typeof name==="string"&&name.length<=64&&isSafeInteger(x)&&isSafeInteger(y)&&Math.abs(x)<=1000000&&Math.abs(y)<=1000000?{type:"create_base",requestId,name,x,y}:null;}\n      const buildingType=(value as {type?:unknown}).type; const level=(value as {level?:unknown}).level; const gridX=(value as {gridX?:unknown}).gridX; const gridY=(value as {gridY?:unknown}).gridY;\n      return typeof buildingType==="string"&&buildingType.length>0&&buildingType.length<=32&&isSafeInteger(level)&&isSafeInteger(gridX)&&isSafeInteger(gridY)&&Math.abs(gridX)<=128&&Math.abs(gridY)<=128?{type:"build",requestId,buildingType,level,gridX,gridY}:null;\n    }\n\n    if (type === "block") {
      const active = (value as { active?: unknown }).active;
      return typeof active === "boolean" ? { type: "block", active } : null;
    }

    if (type === "attack") {
      const requestId = (value as { requestId?: unknown }).requestId;
      const targetId = (value as { targetId?: unknown }).targetId;
      const facingX = (value as { facingX?: unknown }).facingX;
      const facingY = (value as { facingY?: unknown }).facingY;
      if (
        typeof requestId !== "string" ||
        requestId.length === 0 ||
        requestId.length > 64 ||
        typeof targetId !== "string" ||
        targetId.length === 0 ||
        targetId.length > 128 ||
        !isFiniteNumber(facingX) ||
        !isFiniteNumber(facingY) ||
        Math.abs(facingX) > 1 ||
        Math.abs(facingY) > 1 ||
        (facingX === 0 && facingY === 0)
      ) return null;
      return { type: "attack", requestId, targetId, facingX, facingY };
    }
  } catch {
    return null;
  }
  return null;
}
