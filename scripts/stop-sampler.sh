#!/usr/bin/env bash
# Stops a metrics sampler started as its own session/process group, and returns only once no process in that group
# remains. Signalling the whole group also reaches children (for example a psql call the sampler is waiting on), which
# could otherwise keep writing to the log after evidence is hashed. Fails closed if the group cannot be cleared.
set -euo pipefail

pidfile="${1:?usage: stop-sampler.sh <pidfile> [grace_seconds]}"
grace_seconds="${2:-30}"
[ -f "$pidfile" ] || exit 0
pgid="$(tr -d '[:space:]' < "$pidfile")"
[[ "$pgid" =~ ^[0-9]+$ ]] || { echo "invalid sampler pid in $pidfile" >&2; exit 1; }

group_alive() { kill -0 -- "-$pgid" 2>/dev/null; }

if group_alive; then kill -TERM -- "-$pgid" 2>/dev/null || true; fi
for _ in $(seq 1 "$grace_seconds"); do group_alive || break; sleep 1; done
if group_alive; then kill -KILL -- "-$pgid" 2>/dev/null || true; fi
for _ in $(seq 1 10); do group_alive || break; sleep 1; done
if group_alive; then
  echo "sampler process group $pgid is still running; refusing to hash evidence" >&2
  exit 1
fi
