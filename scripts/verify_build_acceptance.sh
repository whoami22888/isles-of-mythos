#!/usr/bin/env bash
# Prompt 040 build-acceptance gate. Refuses production databases and production deploys.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT="${VERIFY_REPORT_PATH:-$ROOT/build-acceptance-report.txt}"
: > "$REPORT"
STATUS=0

log() {
  printf '%s\n' "$*" | tee -a "$REPORT"
}

run_step() {
  local name="$1"
  shift
  log "=== $name ==="
  if "$@" >>"$REPORT" 2>&1; then
    log "PASS $name"
  else
    log "FAIL $name"
    STATUS=1
  fi
}

db_url="${DATABASE_URL:-${TEST_DATABASE_URL:-postgres://postgres:postgres@127.0.0.1:5432/isles_test}}"
environment="${ENVIRONMENT:-test}"

if [[ "${environment}" == "production" || "${environment}" == "prod" ]]; then
  log "REFUSING to run against production (ENVIRONMENT=$environment)"
  exit 1
fi
if [[ "$db_url" == *prod* && "$db_url" != *isles_test* ]]; then
  log "REFUSING to run migrations against a production-looking DATABASE_URL"
  exit 1
fi
if [[ "$db_url" != *isles_test* && "${ALLOW_NONTEST_DB:-}" != "1" ]]; then
  log "REFUSING to run unless DATABASE_URL targets isles_test"
  exit 1
fi

export DATABASE_URL="$db_url"
export NODE_ENV="${NODE_ENV:-test}"
cd "$ROOT"

run_step "typecheck" npm run typecheck --workspace=server
run_step "lint" npm run lint
if [[ -d "$ROOT/server/migrations" ]]; then
  run_step "migrate up (isles_test only)" npm run migrate --workspace=server -- up
  run_step "migrate down (isles_test only)" npm run migrate --workspace=server -- down
  run_step "migrate up restore (isles_test only)" npm run migrate --workspace=server -- up
fi
run_step "server tests" npm test --workspace=server

if command -v python3 >/dev/null 2>&1; then
  if [[ -f "$ROOT/client-godot/tests/test_breeding_recombinator.py" || -f "$ROOT/client-godot/tests/test_onboarding_sequence.py" ]]; then
    run_step "godot python contracts" python3 -m unittest discover -s "$ROOT/client-godot/tests" -p 'test_*.py'
  fi
fi

if [[ -n "${GODOT_BIN:-}" && -x "${GODOT_BIN}" ]]; then
  run_step "godot headless import" "$GODOT_BIN" --headless --path "$ROOT/client-godot" --import --quit
  if [[ -x "$ROOT/scripts/android_apk_pack.py" || -f "$ROOT/scripts/android_apk_pack.py" ]]; then
    log "Android export is delegated to the existing CI export job when GODOT_ANDROID_EXPORT=1"
  fi
else
  log "SKIP godot headless (GODOT_BIN not set)"
fi

if [[ "$STATUS" -eq 0 ]]; then
  log "BUILD ACCEPTANCE: PASS"
else
  log "BUILD ACCEPTANCE: FAIL"
fi
exit "$STATUS"
