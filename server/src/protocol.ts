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
  | { type: "attack"; targetId: string; facingX: number; facingY: number }
  | { type: "dodge"; facingX: number; facingY: number }
  | { type: "block"; active: boolean };

export type ServerMessage =
  | { type: "server_ready"; timestamp: number }
  | { type: "pong"; timestamp: number }
  | { type: "auth_ok"; userId: string }
  | { type: "player_state"; state: unknown }
  | { type: "world_chunk"; requestId: string; chunk: unknown }
  | { type: "combat_result"; targetId: string; damage: number; critical: boolean; killed: boolean; targetHealth: number; status?: string }
  | {
      type: "error";
      code:
        | "INVALID_MESSAGE"
        | "UNSUPPORTED_MESSAGE"
        | "AUTH_REQUIRED"
        | "INVALID_TOKEN"\n        | "COMBAT_COOLDOWN"\n        | "OUT_OF_RANGE"\n        | "NO_STAMINA";
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

    if (type === "attack") {
      const targetId = (value as { targetId?: unknown }).targetId;
      const facingX = (value as { facingX?: unknown }).facingX;
      const facingY = (value as { facingY?: unknown }).facingY;
      if (
        typeof targetId !== "string" ||
        targetId.length === 0 ||
        targetId.length > 128 ||
        !isFiniteNumber(facingX) ||
        !isFiniteNumber(facingY) ||
        Math.abs(facingX) > 1 ||
        Math.abs(facingY) > 1 ||
        (facingX === 0 && facingY === 0)
      ) return null;
      return { type: "attack", targetId, facingX, facingY };
    }
  } catch {
    return null;
  }
  return null;
}
