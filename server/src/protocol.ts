export interface ChunkCoordinate {
  x: number;
  y: number;
}

export type ClientMessage =
  | { type: "ping" }
  | { type: "auth"; token: string }
  | { type: "subscribe_chunks"; requestId: string; chunks: ChunkCoordinate[] };

export type ServerMessage =
  | { type: "server_ready"; timestamp: number }
  | { type: "pong"; timestamp: number }
  | { type: "auth_ok"; userId: string }
  | { type: "world_chunk"; requestId: string; chunk: unknown }
  | {
      type: "error";
      code: "INVALID_MESSAGE" | "UNSUPPORTED_MESSAGE" | "AUTH_REQUIRED" | "INVALID_TOKEN";
    };

function isSafeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value);
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
      ) {
        return null;
      }

      const coordinates: ChunkCoordinate[] = [];
      for (const chunk of chunks) {
        if (
          typeof chunk !== "object" ||
          chunk === null ||
          !("x" in chunk) ||
          !("y" in chunk)
        ) {
          return null;
        }

        const x = (chunk as { x?: unknown }).x;
        const y = (chunk as { y?: unknown }).y;
        if (!isSafeInteger(x) || !isSafeInteger(y) || Math.abs(x) > 1_000_000 || Math.abs(y) > 1_000_000) {
          return null;
        }
        coordinates.push({ x, y });
      }

      return { type: "subscribe_chunks", requestId, chunks: coordinates };
    }
  } catch {
    return null;
  }

  return null;
}
