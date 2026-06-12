#!/usr/bin/env bash
# afk-run.sh — sequential wrapper for the afk- autonomous loop.
# Invokes fresh headless Claude sessions (`claude -p "/afk-step"`) back-to-back
# until the loop reports DONE/BLOCKED or a safety bound trips. Installed by /afk-init.
#
# Config (env vars):
#   AFK_MAX_ITER      iteration ceiling backstop (default 50)
#   AFK_ITER_TIMEOUT  per-iteration wall-clock cap in seconds (default 2700 = 45min)
#   AFK_MODEL         optional --model override for afk-step sessions
#   AFK_BYPASS        set to 1 to add --dangerously-skip-permissions (graduate only
#                     after the skills have a few clean runs)
#   AFK_NTFY_URL      optional ntfy.sh-style URL for push notification on exit

set -u

AFK_MAX_ITER="${AFK_MAX_ITER:-50}"
AFK_ITER_TIMEOUT="${AFK_ITER_TIMEOUT:-2700}"
MAX_CONSEC_FAIL=3

# Always bill the subscription's Agent SDK credit, never an API key.
unset ANTHROPIC_API_KEY

cd "$(dirname "$0")/.." || exit 1   # repo root (script lives in scripts/)
mkdir -p .afk

LOG=".afk/wrapper.log"
log() { printf '%s | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG"; }

# --- single-instance lock (mkdir is atomic; stale lock freed if pid is dead) ---
LOCK=".afk/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  oldpid="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    echo "afk-run: another instance is running (pid $oldpid); exiting." >&2
    exit 1
  fi
  rm -rf "$LOCK"; mkdir "$LOCK" || exit 1
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

notify() {  # $1 = headline, $2 = detail
  log "EXIT: $1 — $2"
  command -v osascript >/dev/null 2>&1 && \
    osascript -e "display notification \"$2\" with title \"afk loop: $1\"" 2>/dev/null
  [ -n "${AFK_NTFY_URL:-}" ] && curl -fsS -m 10 -d "afk loop: $1 — $2" "$AFK_NTFY_URL" >/dev/null 2>&1
  return 0
}

iter=0; consec_fail=0; total_cost="0"

while :; do
  if [ -f .afk/DONE ];    then notify "DONE"    "$(head -c 180 .afk/DONE)";    break; fi
  if [ -f .afk/BLOCKED ]; then notify "BLOCKED" "$(head -c 180 .afk/BLOCKED)"; break; fi

  iter=$((iter + 1))
  if [ "$iter" -gt "$AFK_MAX_ITER" ]; then
    notify "ITER-CAP" "hit $AFK_MAX_ITER iterations without DONE/BLOCKED"; break
  fi

  log "iteration $iter starting (total \$$total_cost so far)"
  extra=()
  [ -n "${AFK_MODEL:-}" ] && extra+=(--model "$AFK_MODEL")
  [ "${AFK_BYPASS:-0}" = "1" ] && extra+=(--dangerously-skip-permissions)

  # perl alarm+exec = portable timeout on macOS (no coreutils dependency)
  perl -e 'alarm shift; exec @ARGV' "$AFK_ITER_TIMEOUT" \
    claude -p "/afk-step" --output-format json "${extra[@]}" \
    > .afk/last.json 2>>"$LOG"
  rc=$?

  if [ $rc -ne 0 ]; then
    consec_fail=$((consec_fail + 1))
    log "iteration $iter FAILED (rc=$rc, consecutive=$consec_fail)"
    if [ "$consec_fail" -ge "$MAX_CONSEC_FAIL" ]; then
      notify "FAILING" "$MAX_CONSEC_FAIL consecutive iteration failures (last rc=$rc)"; break
    fi
    sleep 30; continue
  fi
  consec_fail=0

  # Parse cost + the AFK-STEP summary line from the JSON result (python3 ships with macOS).
  read -r cost summary <<EOF
$(python3 - <<'PY'
import json
try:
    d = json.load(open(".afk/last.json"))
    cost = d.get("total_cost_usd") or 0
    result = (d.get("result") or "").strip().splitlines()
    tail = next((l for l in reversed(result) if l.startswith("AFK-STEP")), result[-1] if result else "(no output)")
    print(f"{cost:.4f} {tail[:300]}")
except Exception as e:
    print(f"0 (parse error: {e})")
PY
)
EOF
  total_cost=$(python3 -c "print(f'{$total_cost + $cost:.4f}')")
  log "iteration $iter done | cost \$$cost | total \$$total_cost | $summary"

  sleep 5
done

log "run finished after $iter iteration(s), notional total \$$total_cost"
