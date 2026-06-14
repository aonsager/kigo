#!/usr/bin/env bash
# afk-tail.sh — live, central view of the afk- loop including worktree work.
#
# Reads the headless afk-step session transcripts (orchestrator + subagents)
# that Claude Code already writes under ~/.claude/projects/<repo-slug>/, and
# renders them in the wrapper's "TS |   · ..." format. Subagent (worktree) lines
# are nested with "↳". Strictly read-only; safe to start/stop any time.
#
# Run it in a second terminal alongside ./scripts/afk-run.sh:
#   ./scripts/afk-tail.sh                 # follow new activity, also persist to .afk/stream.log
#   ./scripts/afk-tail.sh --from-start    # replay current session history first
#   tail -f .afk/stream.log               # ...or tail the persisted file from anywhere
#
# Any args are passed through to afk-tail.py.
set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p .afk
exec python3 -u scripts/afk-tail.py "$@" | tee -a .afk/stream.log
