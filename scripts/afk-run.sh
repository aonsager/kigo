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

# reap_sim_debris — reclaim simulator resources leaked by prior iterations'
# xcodebuild runs. Iterations are strictly sequential, so nothing is using the
# simulator between them and this is always safe to run here.
#
# What actually leaks (2026-07-04 audit): per-runtime daemons (syslogd, apsd,
# homed, widget extensions, …) re-parented to launchd (PPID 1) when a device
# shuts down. They are user-owned and live under the runtime mount path
# (`…/CoreSimulator/Volumes/…`), so they are killable directly — and neither
# `simctl shutdown all` nor a CoreSimulatorService kill ever reaps them. The old
# `pgrep -f CoreSimulator | wc -l > 30` heuristic counted exactly these
# unreapable daemons, so it fired EVERY iteration and hard-killed
# CoreSimulatorService ~every 15 min — dozens of cold service respawns per day,
# each one a roll on the simdiskimaged cold-enumeration wedge (the thing that
# halted the loop on 2026-07-03/04). Do NOT reintroduce a routine killall of
# CoreSimulatorService here: it is reserved for the health-probe recovery
# ladder in ensure_sim_ready(). simdiskimaged is root-owned and left alone —
# the loop must never sudo.
reap_sim_debris() {
  command -v xcrun >/dev/null 2>&1 || return 0
  xcrun simctl shutdown all       >/dev/null 2>&1 || true
  xcrun simctl delete unavailable >/dev/null 2>&1 || true
  # Kill the leaked runtime daemons by mount-path — the actual debris.
  pkill -f 'CoreSimulator/Volumes/' 2>/dev/null || true
}

# ensure_sim_ready — health-probe the CoreSimulator stack and pre-boot the
# pinned test device, so sessions run `xcodebuild test` against a WARM device
# via `-destination id=<udid>` (see CLAUDE.md). The fragile path is destination
# enumeration by name/OS against a cold service; probe→boot→id= avoids it.
# Recovery ladder (verified working with no sudo/reboot on 2026-07-04, even
# with an orphaned root simdiskimaged still running): killall the user-level
# CoreSimulatorService, let `simctl list` respawn a fresh one, re-boot.
SIM_UDID_FILE=".afk/sim-udid"

resolve_sim_udid() {  # iPhone 17 on the iOS 26.4 runtime (pin stays off 26.5 — ADR 0009)
  xcrun simctl list devices available -j 2>/dev/null | python3 -c '
import json, sys
try:
    devices = json.load(sys.stdin)["devices"]
except Exception:
    sys.exit(1)
for runtime, devs in devices.items():
    if "iOS-26-4" in runtime:
        for d in devs:
            if d.get("isAvailable") and d.get("name") == "iPhone 17":
                print(d["udid"]); sys.exit(0)
sys.exit(1)'
}

sim_probe() {  # bounded: a wedged CoreSimulatorService makes simctl hang forever
  perl -e 'alarm shift; exec @ARGV' 30 xcrun simctl list devices available >/dev/null 2>&1
}

ensure_sim_ready() {
  command -v xcrun >/dev/null 2>&1 || return 0
  if ! sim_probe; then
    log "sim health: probe failed — recovery ladder (killall CoreSimulatorService + respawn)"
    killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || true
    sleep 3
    if ! sim_probe; then
      log "sim health: WARN probe still failing after service reset — dispatching anyway (session may recover or do sim-free work; see CLAUDE.md recovery ladder)"
      return 0
    fi
  fi
  local udid
  udid="$(resolve_sim_udid)" || udid=""
  if [ -z "$udid" ]; then
    log "sim health: WARN could not resolve iPhone 17 / iOS 26.4 device — sessions must resolve their own destination"
    rm -f "$SIM_UDID_FILE"
    return 0
  fi
  printf '%s\n' "$udid" > "$SIM_UDID_FILE"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true  # "already booted" is fine
}

# warn_if_swapping — the 2026-07-03/04 halts happened on a 16 GB host ~10 GB
# deep in swap (system JetsamEvent mid-failure). Memory pressure is what tips
# the fragile CoreSimulatorService↔simdiskimaged sync-XPC pairing over, and it
# makes healthy sessions slow enough to trip the iteration timeout. No reboot
# automation by design (user preference) — just a loud, actionable warning.
warn_if_swapping() {
  local used_mb
  used_mb="$(sysctl -n vm.swapusage 2>/dev/null | awk '{print $6}' | tr -d 'M' | cut -d. -f1)"
  if [ "${used_mb:-0}" -gt 8192 ]; then
    log "memory: WARN swap used ${used_mb}MB — close other apps (browser!) or expect slow iterations and simulator wedges"
  fi
}

iter=0; consec_fail=0; consec_timeout=0; total_cost="0"; last_summary="(none yet)"

while :; do
  if [ -f .afk/DONE ];    then notify "DONE"    "$(head -c 180 .afk/DONE)";    break; fi
  if [ -f .afk/BLOCKED ]; then notify "BLOCKED" "$(head -c 180 .afk/BLOCKED)"; break; fi
  if [ -f .afk/STOP ];    then rm -f .afk/STOP; notify "STOPPED" "requested via afk-dash"; break; fi

  iter=$((iter + 1))
  log "iteration $iter starting (total \$$total_cost so far)"
  reap_sim_debris   # clean stale simulator daemons between iterations (safe: sequential)
  ensure_sim_ready  # probe/recover the sim stack, pre-boot the pinned device (.afk/sim-udid)
  warn_if_swapping
  extra=()
  [ -n "${AFK_MODEL:-}" ] && extra+=(--model "$AFK_MODEL")
  [ "${AFK_BYPASS:-0}" = "1" ] && extra+=(--dangerously-skip-permissions)

  # perl alarm+exec = portable timeout on macOS (no coreutils dependency)
  perl -e 'alarm shift; exec @ARGV' "$AFK_ITER_TIMEOUT" \
    claude -p "/afk-step" --output-format json "${extra[@]}" \
    > .afk/last.json 2>>"$LOG"
  rc=$?

  # rc=142 (128 + SIGALRM 14): the perl alarm fired — the iteration ran past
  # AFK_ITER_TIMEOUT and was killed. Two distinct causes (2026-07-04 audit —
  # both actually occurred): a command inside the session wedged (hung test,
  # simulator boot, an await that never resolves), OR the session was healthy
  # but slow (swap-thrashing host, or a deliberate long wait on a subagent) and
  # simply ran past the cap — the 07-03 "WEDGED" halt was the latter, killed
  # mid-GitHub-merge. So: halt after 2 (safety), but say so honestly in the
  # report, and reap the orphans first — SIGALRM kills the claude session but
  # NOT its children, so an orphaned xcodebuild keeps the simulator mid-flight
  # and poisons the next iteration.
  if [ $rc -eq 142 ]; then
    consec_timeout=$((consec_timeout + 1))
    pkill -x xcodebuild 2>/dev/null || true   # -x: exact name; never matches xcodebuildmcp
    sleep 5
    log "iteration $iter TIMED OUT after ${AFK_ITER_TIMEOUT}s (rc=142, consecutive timeouts=$consec_timeout) — hung command OR healthy-but-slow session; orphaned xcodebuild reaped"
    if [ "$consec_timeout" -ge 2 ]; then
      {
        printf 'WEDGED — afk loop halted by the wrapper after %s consecutive iteration timeouts.\n\n' "$consec_timeout"
        printf 'Each iteration exceeded AFK_ITER_TIMEOUT=%ss and was killed by SIGALRM (rc=142).\n' "$AFK_ITER_TIMEOUT"
        printf 'Two possible causes — check the session transcripts in\n'
        printf '~/.claude/projects/<repo-slug>/ (newest .jsonl) BEFORE assuming a hang:\n'
        printf '  1. A command inside the session wedged (hung test, simulator boot, network).\n'
        printf '  2. The session was healthy but SLOW — swap-thrashing host or a long subagent\n'
        printf '     wait — and was killed mid-work (possibly mid-GitHub-mutation: check for\n'
        printf '     half-done merges/comments on the active slice issue).\n'
        printf 'Also check memory: `sysctl vm.swapusage` — >8GB swap used means the host, not\n'
        printf 'the code, is the problem. Orphaned xcodebuild children were reaped by the wrapper.\n\n'
        printf 'For hangs: give slow commands their own inner timeout and enable XCTest\n'
        printf 'execution-time allowances so a stuck test fails fast (see CLAUDE.md).\n\n'
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
