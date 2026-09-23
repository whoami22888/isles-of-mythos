export type ClientMessage =
  | { type: "ping" };

export type ServerMessage =
  | { type: "server_ready"; timestamp: number }
  | { type: "pong"; timestamp: number }
  | { type: "error"; code: "INVALID_MESSAGE" | "UNSUPPORTED_MESSAGE" };

export function parseClientMessage(raw: string): ClientMessage | null {
  try {
    const value: unknown = JSON.parse(raw);

    if (
      typeof value === "object" &&
      value !== null &&
      "type" in value &&
      (value as { type?: unknown }).type === "ping"
    ) {
      return { type: "ping" };
    }
  } catch {
    return null;
  }

  return null;
}
