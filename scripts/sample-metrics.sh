#!/usr/bin/env bash
# Samples server and PostgreSQL metrics once per second while the server process (server.pid) is alive.
# Run under its own process group (see stop-sampler.sh) so that all of its children can be stopped together.
set -uo pipefail
while kill -0 "$(cat server.pid)" 2>/dev/null; do
  printf '%s\n' "--- $(date -Is) ---"
  ps -p "$(cat server.pid)" -o pid=,pcpu=,pmem=,rss=,etime=
  PGPASSWORD=postgres psql "$DATABASE_URL" -Atc "SELECT now(), numbackends, xact_commit, xact_rollback, blks_read, blks_hit FROM pg_stat_database WHERE datname='isles_test';"
  sleep 1
done
