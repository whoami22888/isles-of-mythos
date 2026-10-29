import pg from "pg";

// Diagnostic-only, read-only sampler. Wall time joins server trace timestamps;
// monotonic time records the interval. Samples can miss shorter waits.
const db = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 1 });
const intervalMs = 25;
let busy = false;
let stopped = false;
let sequence = 0;
const started = performance.now();

async function sample() {
  if (busy || stopped) return;
  busy = true;
  try {
    const rows = await db.query("SELECT pid,wait_event_type,wait_event FROM pg_stat_activity WHERE backend_type='client backend' AND state='active' AND wait_event IS NOT NULL");
    if (rows.rows.length > 0) {
      console.log(JSON.stringify({ type: "backend_wait_sample", at: new Date().toISOString(), elapsedMs: performance.now() - started, intervalMs, rows: rows.rows }));
    }
    if (++sequence % 40 === 0) {
      const io = await db.query("SELECT backend_type,object,context,writes,write_time,fsyncs,fsync_time FROM pg_stat_io WHERE object='wal'");
      console.log(JSON.stringify({ type: "global_wal_sample", at: new Date().toISOString(), elapsedMs: performance.now() - started, intervalMs: intervalMs * 40, rows: io.rows, scope: "global_not_per_transaction" }));
    }
  } catch (error) {
    console.error("PostgreSQL wait sampler failed:", error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
    await stop();
  } finally {
    busy = false;
  }
}

async function stop() {
  if (stopped) return;
  stopped = true;
  clearInterval(timer);
  await db.end();
}
const timer = setInterval(sample, intervalMs);
process.once("SIGTERM", stop);
process.once("SIGINT", stop);
