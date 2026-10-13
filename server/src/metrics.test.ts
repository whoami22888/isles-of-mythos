import { afterEach, describe, expect, it, vi } from "vitest";
import {
  recordHttpRequest,
  recordTick,
  renderPrometheusMetrics,
  setActivePlayers,
  setDatabaseUp,
  setWebSocketAuthenticated,
  setWebSocketConnections,
} from "./metrics.js";

function metricValue(metrics: string, name: string): number {
  const match = new RegExp("^" + name + " ([0-9.eE+-]+)$", "m").exec(metrics);
  if (!match) throw new Error("Missing metric " + name);
  return Number(match[1]);
}

describe("metrics", () => {
  afterEach(() => {
    setActivePlayers(0);
    setWebSocketAuthenticated(0);
    setWebSocketConnections(0);
    setDatabaseUp(true);
  });

  it("renders unique active-player count independently from socket count", () => {
    setWebSocketConnections(3);
    setWebSocketAuthenticated(3);
    setActivePlayers(2);

    const metrics = renderPrometheusMetrics();

    expect(metrics).toContain("isles_websocket_connections 3");
    expect(metrics).toContain("isles_websocket_authenticated 3");
    expect(metrics).toContain("isles_active_players 2");
  });

  it("records HTTP errors and tick observations", () => {
    recordHttpRequest(10, 200);
    recordHttpRequest(20, 500);
    recordTick(5);

    const metrics = renderPrometheusMetrics();

    expect(metrics).toMatch(/isles_http_requests_total \d+/);
    expect(metrics).toMatch(/isles_http_errors_total \d+/);
    expect(metrics).toMatch(/isles_http_request_duration_seconds_count \d+/);
    expect(metrics).toMatch(/isles_tick_duration_seconds_count \d+/);
    expect(metrics).toMatch(/isles_tick_duration_seconds_bucket\{le="0.01"\} \d+/);
    expect(metrics).toMatch(/isles_tick_duration_seconds_bucket\{le="\+Inf"\} \d+/);
  });

  it("reports database connectivity state", () => {
    setDatabaseUp(false);
    expect(renderPrometheusMetrics()).toContain("isles_database_up 0");
    setDatabaseUp(true);
    expect(renderPrometheusMetrics()).toContain("isles_database_up 1");
  });
});

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
