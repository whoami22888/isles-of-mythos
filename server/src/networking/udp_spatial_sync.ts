/** Prompt 022: 20 Hz authoritative UDP spatial sync with 32x32 interest and Hermite client extrapolation. */

export const SPATIAL_TICK_HZ = 20;
export const SPATIAL_TICK_MS = 1000 / SPATIAL_TICK_HZ;
export const INTEREST_CHUNK_SIZE = 32;
export const INTEREST_NEIGHBORHOOD = 1;
export const PACKET_LOSS_BUDGET = 0.02;
export const JITTER_BUDGET_MS = 120;

export interface Vec2 {
  x: number;
  y: number;
}

export interface SpatialEntity {
  id: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
}

export interface SpatialClient {
  id: string;
  x: number;
  y: number;
  address: string;
  port: number;
}

export interface SpatialSnapshot {
  sentAtMs: number;
  entities: SpatialEntity[];
}

export interface DatagramTransport {
  send(address: string, port: number, payload: Uint8Array): void;
}

export function interestChunk(x: number, y: number, size = INTEREST_CHUNK_SIZE): { cx: number; cy: number } {
  return { cx: Math.floor(x / size), cy: Math.floor(y / size) };
}

export function isInInterest(observer: Vec2, entity: Vec2, neighborhood = INTEREST_NEIGHBORHOOD, size = INTEREST_CHUNK_SIZE): boolean {
  const a = interestChunk(observer.x, observer.y, size);
  const b = interestChunk(entity.x, entity.y, size);
  return Math.abs(a.cx - b.cx) <= neighborhood && Math.abs(a.cy - b.cy) <= neighborhood;
}

export function encodeSpatialSnapshot(snapshot: SpatialSnapshot): Uint8Array {
  return new TextEncoder().encode(JSON.stringify(snapshot));
}

export function decodeSpatialSnapshot(payload: Uint8Array): SpatialSnapshot {
  const parsed = JSON.parse(new TextDecoder().decode(payload)) as SpatialSnapshot;
  if (!parsed || typeof parsed.sentAtMs !== "number" || !Array.isArray(parsed.entities)) {
    throw new Error("INVALID_SPATIAL_SNAPSHOT");
  }
  return parsed;
}

/** Cubic Hermite basis on t in [0, 1], with velocities expressed per millisecond over dtMs. */
export function hermiteSample(p0: number, v0: number, p1: number, v1: number, t: number, dtMs: number): number {
  const t2 = t * t;
  const t3 = t2 * t;
  const h00 = 2 * t3 - 3 * t2 + 1;
  const h10 = t3 - 2 * t2 + t;
  const h01 = -2 * t3 + 3 * t2;
  const h11 = t3 - t2;
  return h00 * p0 + h10 * v0 * dtMs + h01 * p1 + h11 * v1 * dtMs;
}

export class UdpSpatialSync {
  readonly tickHz: number;
  readonly tickMs: number;
  private readonly transport: DatagramTransport;
  private readonly now: () => number;
  private entities: SpatialEntity[] = [];
  private clients: SpatialClient[] = [];
  private timer: ReturnType<typeof setInterval> | null = null;
  lastBroadcasts = 0;

  constructor(options: { transport: DatagramTransport; tickHz?: number; now?: () => number }) {
    this.transport = options.transport;
    this.tickHz = options.tickHz ?? SPATIAL_TICK_HZ;
    this.tickMs = 1000 / this.tickHz;
    this.now = options.now ?? Date.now;
  }

  setEntities(entities: readonly SpatialEntity[]): void {
    this.entities = entities.map((entity) => ({ ...entity }));
  }

  setClients(clients: readonly SpatialClient[]): void {
    this.clients = clients.map((client) => ({ ...client }));
  }

  tick(nowMs = this.now()): number {
    const snapshot: SpatialSnapshot = { sentAtMs: nowMs, entities: this.entities };
    let sent = 0;
    for (const client of this.clients) {
      const visible = snapshot.entities.filter((entity) => isInInterest(client, entity));
      if (visible.length === 0) continue;
      this.transport.send(client.address, client.port, encodeSpatialSnapshot({ sentAtMs: nowMs, entities: visible }));
      sent += 1;
    }
    this.lastBroadcasts = sent;
    return sent;
  }

  start(): void {
    if (this.timer) return;
    this.timer = setInterval(() => {
      this.tick();
    }, this.tickMs);
    this.timer.unref();
  }

  stop(): void {
    if (!this.timer) return;
    clearInterval(this.timer);
    this.timer = null;
  }
}

interface BufferedPose {
  atMs: number;
  entity: SpatialEntity;
}

const HISTORY_LIMIT = 16;

/** Client receiving node: Hermite interpolation from a jitter-tolerant snapshot buffer. */
export class HermiteSpatialReceiver {
  private readonly history = new Map<string, BufferedPose[]>();

  ingest(snapshot: SpatialSnapshot): void {
    for (const entity of snapshot.entities) {
      const frames = this.history.get(entity.id) ?? [];
      if (frames.some((frame) => frame.atMs === snapshot.sentAtMs)) continue;
      frames.push({ atMs: snapshot.sentAtMs, entity: { ...entity } });
      frames.sort((a, b) => a.atMs - b.atMs);
      if (frames.length > HISTORY_LIMIT) frames.splice(0, frames.length - HISTORY_LIMIT);
      this.history.set(entity.id, frames);
    }
  }

  sample(id: string, atMs: number): Vec2 | null {
    const frames = this.history.get(id);
    if (!frames || frames.length === 0) return null;
    // Render 120ms behind wall-clock so late packets can still fill the interpolation window.
    const renderAtMs = atMs - JITTER_BUDGET_MS;
    let right = frames.findIndex((frame) => frame.atMs > renderAtMs);
    if (right === -1) right = frames.length - 1;
    const left = Math.max(0, right === 0 ? 0 : right - 1);
    const prev = frames[left];
    const next = frames[Math.max(left, right)];
    const dtMs = Math.max(1, next.atMs - prev.atMs);
    let t = (renderAtMs - prev.atMs) / dtMs;
    const maxT = 1 + JITTER_BUDGET_MS / dtMs;
    if (t < 0) t = 0;
    if (t > maxT) t = maxT;
    return {
      x: hermiteSample(prev.entity.x, prev.entity.vx, next.entity.x, next.entity.vx, t, dtMs),
      y: hermiteSample(prev.entity.y, prev.entity.vy, next.entity.y, next.entity.vy, t, dtMs),
    };
  }
}
