import { describe, expect, it } from "vitest";
import {
  recordHttpRequest,
  renderPrometheusMetrics,
  setWebSocketAuthenticated,
  setWebSocketConnections,
} from "./metrics.js";

describe("metrics", () => {
  it("renders process, HTTP and WebSocket metrics", () => {
    recordHttpRequest(12.5, 200);
    recordHttpRequest(25, 503);
    setWebSocketConnections(10);
    setWebSocketAuthenticated(8);

    const metrics = renderPrometheusMetrics();

    expect(metrics).toContain("isles_process_uptime_seconds");
    expect(metrics).toContain("isles_process_resident_memory_bytes");
    expect(metrics).toContain("isles_http_requests_total");
    expect(metrics).toContain("isles_http_errors_total 1");
    expect(metrics).toContain("isles_http_request_duration_seconds_count 2");
    expect(metrics).toContain("isles_websocket_connections 10");
    expect(metrics).toContain("isles_websocket_authenticated 8");
  });
});
