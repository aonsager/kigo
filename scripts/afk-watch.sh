#!/usr/bin/env bash
# afk-watch.sh — one command to run the loop and watch it live.
#
# Starts ./scripts/afk-run.sh in the background (its own log still goes to
# .afk/wrapper.log) and follows the worktree-inclusive activity stream
# (./scripts/afk-tail.sh) in the console. Ctrl-C stops both.
#
# Any args are passed through to afk-tail.sh (e.g. --from-start).
set -u
cd "$(dirname "$0")/.." || exit 1

./scripts/afk-run.sh >/dev/null 2>&1 &
loop_pid=$!
echo "afk-run started (pid $loop_pid) — wrapper log → .afk/wrapper.log, stream → .afk/stream.log"
echo "Ctrl-C stops the loop and this view."
trap 'kill "$loop_pid" 2>/dev/null' INT TERM EXIT

./scripts/afk-tail.sh "$@"
