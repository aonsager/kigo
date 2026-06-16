#!/usr/bin/env bash
# afk-run.sh — sequential wrapper for the afk- autonomous loop.
# Invokes fresh headless Claude sessions (`claude -p "/afk-step"`) back-to-back
# until the loop reports DONE/BLOCKED or a safety bound trips. Installed by /afk-init.
#
# Config (env vars):
#   AFK_ITER_TIMEOUT  per-iteration wall-clock cap in seconds (default 2700 = 45min)
#   AFK_MODEL         --model for the afk-step ORCHESTRATOR session (default
#                     "sonnet"). This drives the loop logic — phase
#                     derivation, dispatch/halt/retry/bounce decisions, GitHub
#                     ops, reading subagent results — across ~60 turns/iteration,
#                     and was ~73% of the loop's token bill when left on Opus.
#                     Sonnet is sufficient because every judgment-critical fork
#                     pins its OWN model regardless of this orchestrator: the
#                     implementer escalates to opus on attempts 2-3, and the
#                     audit→main gate runs an opus subagent. The skills were
#                     explicitly designed for a cheap orchestrator (see the
#                     "parent model … may itself be a cheap orchestrator" note in
#                     afk-advance). Set AFK_MODEL=opus to revert.
#   AFK_BYPASS        set to 1 to add --dangerously-skip-permissions (graduate only
#                     after the skills have a few clean runs)
#   AFK_NTFY_URL      optional ntfy.sh-style URL for push notification on exit

set -u

AFK_ITER_TIMEOUT="${AFK_ITER_TIMEOUT:-2700}"
AFK_MODEL="${AFK_MODEL:-sonnet}"   # orchestrator model; see header
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

iter=0; consec_fail=0; consec_timeout=0; total_cost="0"; last_summary="(none yet)"

while :; do
  if [ -f .afk/DONE ];    then notify "DONE"    "$(head -c 180 .afk/DONE)";    break; fi
  if [ -f .afk/BLOCKED ]; then notify "BLOCKED" "$(head -c 180 .afk/BLOCKED)"; break; fi

  iter=$((iter + 1))
  log "iteration $iter starting (total \$$total_cost so far)"
  extra=()
  [ -n "${AFK_MODEL:-}" ] && extra+=(--model "$AFK_MODEL")
  [ "${AFK_BYPASS:-0}" = "1" ] && extra+=(--dangerously-skip-permissions)

  # perl alarm+exec = portable timeout on macOS (no coreutils dependency)
  perl -e 'alarm shift; exec @ARGV' "$AFK_ITER_TIMEOUT" \
    claude -p "/afk-step" --output-format json "${extra[@]}" \
    > .afk/last.json 2>>"$LOG"
  rc=$?

  # rc=142 (128 + SIGALRM 14): the perl alarm fired — the iteration ran past
  # AFK_ITER_TIMEOUT and was killed. That almost always means a command INSIDE
  # the session wedged (a hung test, network call, simulator boot, or an await
  # that never resolves), not a transient crash — and it tends to repeat
  # identically. So treat it as its own class: halt faster (2, not 3) and, since
  # the killed session could not record its own forensics, have the WRAPPER write
  # .afk/BLOCKED with a WEDGED diagnosis. The real fix lives downstream (wrap slow
  # commands in their own timeout so they fail fast); this is the backstop.
  if [ $rc -eq 142 ]; then
    consec_timeout=$((consec_timeout + 1))
    log "iteration $iter TIMED OUT after ${AFK_ITER_TIMEOUT}s (rc=142, consecutive timeouts=$consec_timeout) — a command in the session likely hung"
    if [ "$consec_timeout" -ge 2 ]; then
      {
        printf 'WEDGED — afk loop halted by the wrapper after %s consecutive iteration timeouts.\n\n' "$consec_timeout"
        printf 'Each iteration exceeded AFK_ITER_TIMEOUT=%ss and was killed by SIGALRM (rc=142),\n' "$AFK_ITER_TIMEOUT"
        printf 'meaning a command INSIDE the afk-step session hung rather than failing fast\n'
        printf '(hung test, network call, simulator boot, or an await that never resolves).\n'
        printf 'The session was killed mid-flight, so it could not record its own forensics.\n\n'
        printf 'Where to look: the slice/phase from the last good iteration below, and that\n'
        printf "slice's build/test command. Fix: give slow commands their own inner timeout and\n"
        printf 'enable XCTest execution-time allowances so a stuck test fails fast and visibly\n'
        printf 'instead of consuming the whole iteration budget (see CLAUDE.md build/test notes).\n\n'
        printf 'Last good iteration summary:\n  %s\n\n' "$last_summary"
        printf 'Recent wrapper log:\n'
        tail -n 15 "$LOG"
      } > .afk/BLOCKED
      notify "WEDGED" "$consec_timeout consecutive ${AFK_ITER_TIMEOUT}s timeouts — likely a hung command; see .afk/BLOCKED"
      break
    fi
    sleep 30; continue
  fi

  if [ $rc -ne 0 ]; then
    consec_fail=$((consec_fail + 1))
    log "iteration $iter FAILED (rc=$rc, consecutive=$consec_fail)"
    if [ "$consec_fail" -ge "$MAX_CONSEC_FAIL" ]; then
      notify "FAILING" "$MAX_CONSEC_FAIL consecutive iteration failures (last rc=$rc)"; break
    fi
    sleep 30; continue
  fi
  consec_fail=0; consec_timeout=0

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
  last_summary="$summary"
  log "iteration $iter done | cost \$$cost | total \$$total_cost | $summary"

  sleep 5
done

log "run finished after $iter iteration(s), notional total \$$total_cost"
