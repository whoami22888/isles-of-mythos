#!/usr/bin/env node
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const expectedPlayers = [1, 50, 250, 1000];
const expectedLoadTestPlayers = [10, 50, 100, 500, 1000];
function need(condition, message) {
  if (!condition) throw new Error(message);
}

export function validateReport(report) {
  need(report?.event === "sustained_load_complete", "Missing complete marker");
  need(Array.isArray(report.scenarios) && report.scenarios.length === 4, "Expected 1/50/250/1000 matrix");
  need(Array.isArray(report.loadTestScenarios) && report.loadTestScenarios.length === expectedLoadTestPlayers.length,
    "Expected 10/50/100/500/1000 load-test matrix");
  for (let index = 0; index < expectedLoadTestPlayers.length; index++) {
    const players = expectedLoadTestPlayers[index];
    const scenario = report.loadTestScenarios[index];
    const ws = scenario?.websocket;
    need(scenario?.players === players, "Missing load-test player scenario " + players);
    need(scenario.http?.endpoint === "world_chunks" && scenario.http.requests === 100 && scenario.http.errors === 0,
      "HTTP load-test failure " + players);
    need(ws?.requestedPlayers === players && ws.connected === players && ws.authenticated === players && ws.errors === 0,
      "Load-test WebSocket counts " + players);
    need(ws.pings > 0 && ws.pongs === ws.pings && ws.pingSuccessRate === 1, "Load-test ping/pong " + players);
    for (const [name, value] of [["HTTP p95", scenario.http.p95Ms], ["HTTP p99", scenario.http.p99Ms],
      ["WebSocket ping p95", ws.pingP95Ms], ["WebSocket ping p99", ws.pingP99Ms]]) {
      need(Number.isFinite(value) && value >= 0, "Missing load-test " + name + " for " + players);
    }
    need(ws.networkBytesSent > 0 && ws.networkBytesReceived > 0, "Missing load-test bandwidth " + players);
  }

  for (let index = 0; index < expectedPlayers.length; index++) {
    const players = expectedPlayers[index];
    const scenario = report.scenarios[index];
    const ws = scenario?.websocket;
    need(scenario?.players === players, "Missing player scenario " + players);
    need(scenario.http?.endpoint === "world_chunks", "HTTP latency must measure the gameplay world-chunk endpoint for " + players);
    need(scenario.http?.requests === 100 && scenario.http.errors === 0, "HTTP failure " + players);
    need(ws?.requestedPlayers === players && ws.connected === players && ws.authenticated === players && ws.errors === 0, "WebSocket counts " + players);
    need(ws.pings > 0 && ws.pongs === ws.pings && ws.pingSuccessRate === 1, "Ping/pong " + players);

    for (const [name, value] of [
      ["HTTP p95", scenario.http.p95Ms],
      ["HTTP p99", scenario.http.p99Ms],
      ["WebSocket gameplay p95", ws.gameplayP95Ms],
      ["WebSocket gameplay p99", ws.gameplayP99Ms],
      ["WebSocket authentication p95", ws.authP95Ms],
      ["WebSocket authentication p99", ws.authP99Ms],
      ["WebSocket ping p95", ws.pingP95Ms],
      ["WebSocket ping p99", ws.pingP99Ms],
    ]) {
      need(Number.isFinite(value) && value >= 0, "Missing " + name + " for " + players);
    }

    const expectedGameplaySamples = Math.min(players, 100) * 2;
    need(ws.gameplayLatencySamples === expectedGameplaySamples, "Expected " + expectedGameplaySamples + " gameplay latency samples for " + players);
    need(
      scenario.http.p95Ms <= 150 && scenario.http.p99Ms <= 300 &&
      ws.gameplayP95Ms <= 150 && ws.gameplayP99Ms <= 300,
      "Approved gameplay latency SLO exceeded for " + players,
    );

    const craft = ws.gameplayCraft;
    need(
      craft?.action === "craft" && craft.recipeId === "tool.wooden-club" &&
      typeof craft.transactionId === "string" && craft.transactionId.length > 0 &&
      craft.persisted === true && Number.isFinite(craft.latencyMs) && craft.latencyMs >= 0 &&
      craft.persistenceEvidence?.ledger?.transactionId === craft.transactionId &&
      craft.persistenceEvidence?.ledger?.recipeId === craft.recipeId &&
      craft.persistenceEvidence?.inventoryAfter?.["resource.wood"] === 0 &&
      craft.persistenceEvidence?.inventoryAfter?.["tool.wooden-club"] === 1,
      "Missing or inconsistent durable gameplayCraft evidence " + players,
    );
    const mutation = ws.gameplayMutation;
    need(
      mutation?.action === "gather_resource" && typeof mutation.resourceId === "string" && mutation.resourceId.length > 0 &&
      typeof mutation.itemId === "string" && mutation.itemId.length > 0 && Number.isSafeInteger(mutation.quantity) &&
      mutation.quantity > 0 && mutation.persisted === true &&
      Number.isFinite(mutation.latencyMs) && mutation.latencyMs >= 0 &&
      Number.isSafeInteger(mutation.persistenceEvidence?.inventoryQuantity) &&
      mutation.persistenceEvidence.inventoryQuantity >= mutation.quantity &&
      typeof mutation.persistenceEvidence?.depletedUntil === "string" &&
      Number.isFinite(Date.parse(mutation.persistenceEvidence.depletedUntil)),
      "Missing or inconsistent durable gameplayMutation evidence " + players,
    );
    need(ws.networkBytesSent > 0 && ws.networkBytesReceived > 0, "Missing bandwidth " + players);
  }

  const domain = new Map((report.domainScenarios ?? []).map(item => [item.name, item]));
  const guild = domain.get("large_guild_battle");
  const naval = domain.get("large_naval_battle");
  const boss = domain.get("world_boss");
  const bases = domain.get("thousands_of_player_bases");
  need(guild?.persisted && guild.participants === 500 && guild.actions === 500 &&
    BigInt(guild.attackerScore) > 0n && BigInt(guild.defenderScore) > 0n, "Missing guild battle evidence");
  need(naval?.persisted && naval.actions === 250 && naval.eventsPersisted === 250 &&
    naval.totalDamage > 0, "Missing naval battle evidence");
  need(boss?.persisted && boss.contributors === 250 && boss.contributionsPersisted === 250, "Missing world boss evidence");
  need(bases?.persisted && bases.basesPersisted === 5000 && bases.lookups === 50 &&
    Number.isFinite(bases.p95Ms) && Number.isFinite(bases.p99Ms), "Missing 5,000 bases evidence");

  const metrics = report.serverMetrics;
  need(Number.isInteger(metrics?.postgresServerVersion) &&
    metrics.postgresServerVersion >= 180000 && metrics.postgresServerVersion < 190000,
    "PostgreSQL 18 server version evidence missing or incompatible");
  need(Number.isFinite(metrics?.tickCount) && metrics.tickCount > 0 &&
    Number.isFinite(metrics.averageTickMs) && metrics.averageTickMs >= 0, "Missing server tick evidence");
  need(Number.isFinite(metrics.tickP95Ms) && metrics.tickP95Ms >= 0 && metrics.tickP95Ms <= 40,
    "Server tick p95 must be <= 40ms");
  need(Number.isFinite(metrics.tickP99Ms) && metrics.tickP99Ms >= 0 && metrics.tickP99Ms <= 50,
    "Server tick p99 must be <= 50ms");
  for (const key of [
    "residentMemoryBytes", "heapUsedBytes", "cpuUserSeconds", "cpuSystemSeconds",
    "httpRequestsTotal", "httpErrorsTotal", "networkBytesSent", "networkBytesReceived",
  ]) {
    need(Number.isFinite(metrics?.[key]) && metrics[key] >= 0, "Missing metric " + key);
  }
  need(report.clientMetrics?.status === "not_measured_in_headless_ci" &&
    typeof report.clientMetrics.reason === "string", "Must disclose device FPS/GPU unmeasured");
  return true;
}

if (process.argv[2] === "--self-test") {
  const report = {
    event: "sustained_load_complete",
    scenarios: expectedPlayers.map(players => ({
      players,
      http: { endpoint: "world_chunks", requests: 100, errors: 0, p95Ms: 1, p99Ms: 1 },
      websocket: {
        requestedPlayers: players, connected: players, authenticated: players, errors: 0,
        pings: 1, pongs: 1, pingSuccessRate: 1,
        gameplayLatencySamples: Math.min(players, 100) * 2,
        gameplayP95Ms: 1, gameplayP99Ms: 1, authP95Ms: 1, authP99Ms: 1,
        pingP50Ms: 1, pingP95Ms: 1, pingP99Ms: 1,
        gameplayCraft: {
          action: "craft", recipeId: "tool.wooden-club", transactionId: "tx", latencyMs: 1, persisted: true,
          persistenceEvidence: { ledger: { transactionId: "tx", recipeId: "tool.wooden-club" }, inventoryAfter: { "resource.wood": 0, "tool.wooden-club": 1 } },
        },
        gameplayMutation: {
          action: "gather_resource", resourceId: "r", itemId: "resource.wood", quantity: 1, latencyMs: 1, persisted: true,
          persistenceEvidence: { inventoryQuantity: 1, depletedUntil: new Date(Date.now() + 60000).toISOString() },
        },
        networkBytesSent: 1, networkBytesReceived: 1,
      },
    })),
    domainScenarios: [
      { name: "large_guild_battle", participants: 500, actions: 500, attackerScore: "1", defenderScore: "1", persisted: true },
      { name: "large_naval_battle", actions: 250, eventsPersisted: 250, totalDamage: 1, persisted: true },
      { name: "world_boss", contributors: 250, contributionsPersisted: 250, persisted: true },
      { name: "thousands_of_player_bases", basesPersisted: 5000, lookups: 50, p95Ms: 1, p99Ms: 1, persisted: true },
    ],
    serverMetrics: {
      postgresServerVersion: 180006, tickCount: 1, averageTickMs: 1, tickP95Ms: 20, tickP99Ms: 40,
      residentMemoryBytes: 1, heapUsedBytes: 1, cpuUserSeconds: 1, cpuSystemSeconds: 1,
      httpRequestsTotal: 1, httpErrorsTotal: 0, networkBytesSent: 1, networkBytesReceived: 1,
    },
    clientMetrics: { status: "not_measured_in_headless_ci", reason: "device test required" },
  };
  report.loadTestScenarios = expectedLoadTestPlayers.map(players => {
    const existing = report.scenarios.find(scenario => scenario.players === players);
    if (existing) return existing;
    return {
      players,
      http: { endpoint: "world_chunks", requests: 100, errors: 0, p95Ms: 1, p99Ms: 1 },
      websocket: {
        requestedPlayers: players, connected: players, authenticated: players, errors: 0,
        pings: 1, pongs: 1, pingSuccessRate: 1, pingP95Ms: 1, pingP99Ms: 1,
        networkBytesSent: 1, networkBytesReceived: 1,
      },
    };
  });
  assert.equal(validateReport(report), true);
  const missingLoadMatrix = structuredClone(report);
  missingLoadMatrix.loadTestScenarios.pop();
  assert.throws(() => validateReport(missingLoadMatrix), /load-test matrix/);
  const missingCraft = structuredClone(report);
  delete missingCraft.scenarios[0].websocket.gameplayCraft;
  assert.throws(() => validateReport(missingCraft), /gameplayCraft/);
  const missingMutation = structuredClone(report);
  missingMutation.scenarios[0].websocket.gameplayMutation.persisted = false;
  assert.throws(() => validateReport(missingMutation), /gameplayMutation/);
  const missingCraftLedger = structuredClone(report);
  delete missingCraftLedger.scenarios[0].websocket.gameplayCraft.persistenceEvidence.ledger.transactionId;
  assert.throws(() => validateReport(missingCraftLedger), /gameplayCraft/);
  const badMutationInventory = structuredClone(report);
  badMutationInventory.scenarios[0].websocket.gameplayMutation.persistenceEvidence.inventoryQuantity = 0;
  assert.throws(() => validateReport(badMutationInventory), /gameplayMutation/);
  const badMutationDepletion = structuredClone(report);
  badMutationDepletion.scenarios[0].websocket.gameplayMutation.persistenceEvidence.depletedUntil = "not-a-date";
  assert.throws(() => validateReport(badMutationDepletion), /gameplayMutation/);
  const badTick = structuredClone(report);
  badTick.serverMetrics.tickP95Ms = 41;
  assert.throws(() => validateReport(badTick), /tick p95/);
  const badHttp = structuredClone(report);
  badHttp.scenarios[0].http.p99Ms = 301;
  assert.throws(() => validateReport(badHttp), /latency SLO/);
  const badGameplay = structuredClone(report);
  badGameplay.scenarios[0].websocket.gameplayP99Ms = 301;
  assert.throws(() => validateReport(badGameplay), /latency SLO/);
  console.log("Validator self-test PASS");
} else {
  if (!process.argv[2]) throw new Error("Usage: node scripts/validate-performance-report.mjs <report.json> | --self-test");
  validateReport(JSON.parse(readFileSync(process.argv[2], "utf8")));
  console.log("Performance report PASS");
}
