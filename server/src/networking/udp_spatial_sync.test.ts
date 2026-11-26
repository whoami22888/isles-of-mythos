import { describe, expect, it } from "vitest";
import {
  HermiteSpatialReceiver,
  INTEREST_CHUNK_SIZE,
  JITTER_BUDGET_MS,
  PACKET_LOSS_BUDGET,
  SPATIAL_TICK_HZ,
  UdpSpatialSync,
  decodeSpatialSnapshot,
  hermiteSample,
  isInInterest,
  type DatagramTransport,
  type SpatialSnapshot,
} from "./udp_spatial_sync.js";

class MemoryTransport implements DatagramTransport {
  readonly packets: Array<{ address: string; port: number; payload: Uint8Array }> = [];

  send(address: string, port: number, payload: Uint8Array): void {
    this.packets.push({ address, port, payload: payload.slice() });
  }
}

describe("UDP spatial sync (Prompt 022)", () => {
  it("runs a 20 Hz tick and only broadcasts entities inside 32x32 interest neighborhoods", () => {
    expect(SPATIAL_TICK_HZ).toBe(20);
    expect(INTEREST_CHUNK_SIZE).toBe(32);
    const transport = new MemoryTransport();
    const sync = new UdpSpatialSync({ transport, now: () => 1_000 });
    expect(sync.tickMs).toBe(50);
    sync.setEntities([
      { id: "near", x: 4, y: 4, vx: 1, vy: 0 },
      { id: "far", x: 400, y: 400, vx: 0, vy: 0 },
    ]);
    sync.setClients([{ id: "c1", x: 2, y: 2, address: "127.0.0.1", port: 4001 }]);
    expect(isInInterest({ x: 2, y: 2 }, { x: 4, y: 4 })).toBe(true);
    expect(isInInterest({ x: 2, y: 2 }, { x: 400, y: 400 })).toBe(false);
    expect(sync.tick()).toBe(1);
    expect(transport.packets).toHaveLength(1);
    const snapshot = decodeSpatialSnapshot(transport.packets[0].payload);
    expect(snapshot.entities.map((entity) => entity.id)).toEqual(["near"]);
  });

  it("keeps interpolated movement smooth under 2% loss and 120ms jitter", () => {
    const receiver = new HermiteSpatialReceiver();
    const vx = 8 / 1000; // tiles per millisecond
    const durationMs = 5_000;
    const tickMs = 50;
    let dropped = 0;
    let sent = 0;
    const delayed: Array<{ deliverAt: number; snapshot: SpatialSnapshot }> = [];

    for (let time = 0, tick = 0; time <= durationMs; time += tickMs, tick += 1) {
      const entity = { id: "ship", x: vx * time, y: 0, vx, vy: 0 };
      sent += 1;
      // Deterministic 2% loss (every 50th tick) plus up to 120ms delivery jitter.
      if (tick % 50 === 49) {
        dropped += 1;
        continue;
      }
      const jitter = (tick * 17) % (JITTER_BUDGET_MS + 1);
      delayed.push({ deliverAt: time + jitter, snapshot: { sentAtMs: time, entities: [entity] } });
    }

    delayed.sort((a, b) => a.deliverAt - b.deliverAt || a.snapshot.sentAtMs - b.snapshot.sentAtMs);
    let deliverIndex = 0;
    const positions: number[] = [];
    const truths: number[] = [];
    for (let time = tickMs * 2; time <= durationMs - JITTER_BUDGET_MS; time += 16) {
      while (deliverIndex < delayed.length && delayed[deliverIndex].deliverAt <= time) {
        receiver.ingest(delayed[deliverIndex].snapshot);
        deliverIndex += 1;
      }
      const sampled = receiver.sample("ship", time);
      expect(sampled).not.toBeNull();
      positions.push(sampled!.x);
      truths.push(vx * Math.max(0, time - JITTER_BUDGET_MS));
    }

    expect(dropped / sent).toBeCloseTo(PACKET_LOSS_BUDGET, 1);

    let maxStep = 0;
    let maxError = 0;
    for (let i = 1; i < positions.length; i += 1) {
      maxStep = Math.max(maxStep, Math.abs(positions[i] - positions[i - 1]));
      maxError = Math.max(maxError, Math.abs(positions[i] - truths[i]));
    }
    // 16ms * vx = 0.128 tiles; allow a generous smoothness cap well below a dropped-tick teleport (0.4).
    expect(maxStep).toBeLessThan(0.3);
    expect(maxError).toBeLessThan(0.75);
    expect(hermiteSample(0, 1, 10, 1, 0, 10)).toBeCloseTo(0);
    expect(hermiteSample(0, 1, 10, 1, 1, 10)).toBeCloseTo(10);
  });
});
