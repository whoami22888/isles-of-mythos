import { describe, expect, it, vi } from "vitest";
import { recordTick, renderPrometheusMetrics } from "./metrics.js";

function metricValue(metrics: string, name: string): number {
  const match = new RegExp("^" + name + " ([0-9.eE+-]+)$", "m").exec(metrics);
  if (!match) throw new Error("Missing metric " + name);
  return Number(match[1]);
}

describe("server tick-rate metrics", () => {
  it("reports measured cadence and detects a sub-20-Hz window", () => {
    let now = process.hrtime.bigint();
    const clock = vi.spyOn(process.hrtime, "bigint").mockImplementation(() => now);
    try {
      recordTick(1);
      for (let tick = 0; tick < 31; tick += 1) {
        now += 33_000_000n;
        recordTick(1);
      }

      const onCadence = renderPrometheusMetrics();
      expect(metricValue(onCadence, "isles_tick_rate_hz")).toBeGreaterThanOrEqual(20);
      expect(metricValue(onCadence, "isles_tick_rate_window_seconds")).toBeGreaterThanOrEqual(1);

      for (let tick = 0; tick < 5; tick += 1) {
        now += 250_000_000n;
        recordTick(1);
      }

      const belowCadence = renderPrometheusMetrics();
      expect(metricValue(belowCadence, "isles_tick_rate_hz")).toBeLessThan(20);
      expect(metricValue(belowCadence, "isles_tick_rate_window_seconds")).toBeGreaterThanOrEqual(1);
    } finally {
      clock.mockRestore();
    }
  });
});
