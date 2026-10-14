export interface RequestReplayCache<T> {
  lookup(userId: string, requestId: string, fingerprint: string):
    | { kind: "miss" }
    | { kind: "hit"; response: T }
    | { kind: "conflict" };
  remember(userId: string, requestId: string, fingerprint: string, response: T): void;
}

export async function runReplayableRequest<T>(
  replay: RequestReplayCache<T>,
  pending: Map<string, Promise<T>>,
  userId: string,
  requestId: string,
  fingerprint: string,
  operation: () => Promise<T> | T,
  conflict: T,
): Promise<T> {
  const replayResult = replay.lookup(userId, requestId, fingerprint);
  if (replayResult.kind === "hit") return replayResult.response;
  if (replayResult.kind === "conflict") return conflict;

  const key = userId + ":" + requestId;
  const existing = pending.get(key);
  if (existing) return existing;

  const task = Promise.resolve().then(operation).then((response) => {
    replay.remember(userId, requestId, fingerprint, response);
    return response;
  });
  pending.set(key, task);
  try {
    return await task;
  } finally {
    if (pending.get(key) === task) pending.delete(key);
  }
}
