import { afterEach, describe, expect, it } from "vitest";
import {
  recordHttpRequest,
  recordTick,
  renderPrometheusMetrics,
  setActivePlayers,
  setDatabaseUp,
  setWebSocketAuthenticated,
  setWebSocketConnections,
} from "./metrics.js";

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
  });

  it("reports database connectivity state", () => {
    setDatabaseUp(false);
    expect(renderPrometheusMetrics()).toContain("isles_database_up 0");
    setDatabaseUp(true);
    expect(renderPrometheusMetrics()).toContain("isles_database_up 1");
  });
});
