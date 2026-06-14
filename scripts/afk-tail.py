#!/usr/bin/env python3
"""afk-tail.py — central live view of the afk- loop, including worktree work.

The afk wrapper runs each iteration as a fresh headless `claude -p "/afk-step"`
with `--output-format json`, so the wrapper log only gets start/done lines. The
actual blow-by-blow — including the slice work that runs in a worktree as an
Agent-tool subagent — is persisted by Claude Code to the session transcript:

    ~/.claude/projects/<repo-slug>/<session-uuid>.jsonl          (orchestrator)
    ~/.claude/projects/<repo-slug>/<session-uuid>/subagents/*.jsonl  (subagents)

This script follows both, renders each assistant text block and tool-call title
in the wrapper's `TS |   · ...` format, and nests subagent lines (`↳`) so the
worktree work is visible and attributable. It is strictly read-only: it never
touches the loop, the transcripts, or any skill.

Usage:
    python3 scripts/afk-tail.py [--from-start] [--repo-dir DIR] [TRANSCRIPT_DIR]

  --from-start   render existing transcript history too (default: only new
                 activity from the moment you start watching)
  --repo-dir     repo whose transcripts to follow (default: this repo)
  TRANSCRIPT_DIR explicit ~/.claude/projects/<slug> dir (overrides derivation)
"""
import json
import os
import sys
import time
from datetime import datetime, timezone

POLL_SECONDS = 1.0


def transcript_dir_for(repo_dir: str) -> str:
    """Claude Code keys each transcript dir by cwd: '/' and '.' become '-'."""
    abspath = os.path.abspath(repo_dir)
    slug = abspath.replace("/", "-").replace(".", "-")
    return os.path.expanduser(f"~/.claude/projects/{slug}")


def fmt_ts(iso: str | None) -> str:
    """Match the wrapper's UTC '%Y-%m-%dT%H:%M:%SZ' format."""
    if iso:
        try:
            dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
            return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            pass
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def tool_desc(name: str, inp: dict) -> str:
    if not isinstance(inp, dict):
        return ""
    if name == "Bash":
        d = inp.get("description")
        if d:
            return d
        cmd = (inp.get("command") or "").strip().splitlines()
        return cmd[0][:100] if cmd else ""
    if name in ("Read", "Edit", "Write", "MultiEdit", "NotebookEdit"):
        fp = inp.get("file_path") or inp.get("notebook_path") or ""
        return fp.split("/")[-1] if fp else ""
    if name in ("Agent", "Task"):
        return "▷ subagent: " + (inp.get("description") or inp.get("subagent_type") or "")
    if name == "Skill":
        s = inp.get("skill") or ""
        a = inp.get("args") or ""
        return (s + (" " + a if a else "")).strip()
    if name in ("Grep", "Glob"):
        return inp.get("pattern", "")
    # generic fallbacks
    for k in ("description", "query", "prompt", "url", "path"):
        v = inp.get(k)
        if v:
            return str(v)[:100]
    return ""


def render(raw: str, sub_tag: str | None, out) -> None:
    """Render one transcript JSONL line. sub_tag=None for the orchestrator;
    a short agent id (e.g. 'a144') for a subagent."""
    try:
        d = json.loads(raw)
    except json.JSONDecodeError:
        return
    if d.get("type") != "assistant":
        return
    msg = d.get("message")
    if not isinstance(msg, dict):
        return
    ts = fmt_ts(d.get("timestamp"))
    # orchestrator:  "  · ..."   subagent:  "    ↳a144 ..."
    bullet = f"  ↳{sub_tag} " if sub_tag else "  · "
    for blk in (msg.get("content") or []):
        if not isinstance(blk, dict):
            continue
        t = blk.get("type")
        if t == "text":
            for line in (blk.get("text") or "").splitlines():
                line = line.rstrip()
                if line:
                    out.write(f"{ts} | {bullet}{line}\n")
        elif t == "tool_use":
            name = blk.get("name", "?")
            desc = tool_desc(name, blk.get("input") or {})
            label = f"{name.lower()}: {desc}" if desc else name.lower()
            out.write(f"{ts} | {bullet}{label}\n")
    out.flush()


def iter_files(tdir: str):
    """Yield (path, sub_tag) for every transcript file under tdir.
    sub_tag is None for top-level session files, else a short agent id."""
    try:
        entries = os.listdir(tdir)
    except FileNotFoundError:
        return
    for name in entries:
        full = os.path.join(tdir, name)
        if name.endswith(".jsonl") and os.path.isfile(full):
            yield full, None
        elif os.path.isdir(full):
            subdir = os.path.join(full, "subagents")
            try:
                subs = os.listdir(subdir)
            except FileNotFoundError:
                continue
            for s in subs:
                if s.startswith("agent-") and s.endswith(".jsonl"):
                    # short id: chars after 'agent-', trimmed
                    tag = s[len("agent-"):].rstrip(".jsonl")[:4] or "sub"
                    yield os.path.join(subdir, s), tag


def main() -> int:
    args = sys.argv[1:]
    from_start = "--from-start" in args
    args = [a for a in args if a != "--from-start"]
    repo_dir = "."
    if "--repo-dir" in args:
        i = args.index("--repo-dir")
        repo_dir = args[i + 1]
        del args[i:i + 2]
    tdir = args[0] if args else transcript_dir_for(repo_dir)

    out = sys.stdout
    out.write(f"# afk-tail watching {tdir}\n")
    out.write(f"# {'replaying history then ' if from_start else ''}following live activity "
              f"(orchestrator '·', subagents '↳')\n")
    out.flush()

    offsets: dict[str, int] = {}
    started = False

    while True:
        for path, tag in iter_files(tdir):
            try:
                size = os.path.getsize(path)
            except OSError:
                continue
            if path not in offsets:
                # On the very first scan, seed existing files to EOF (unless
                # --from-start) so we only show new activity. Files that appear
                # *after* startup (a new iteration / a freshly-spawned subagent)
                # are always read from byte 0.
                offsets[path] = 0 if (from_start or started) else size
            if size < offsets[path]:  # file truncated/rotated
                offsets[path] = 0
            if size <= offsets[path]:
                continue
            try:
                with open(path, "rb") as fh:
                    fh.seek(offsets[path])
                    data = fh.read()
            except OSError:
                continue
            nl = data.rfind(b"\n")
            if nl == -1:
                continue  # no complete line yet
            chunk = data[:nl + 1]
            offsets[path] += len(chunk)
            for line in chunk.decode("utf-8", "replace").splitlines():
                render(line, tag, out)
        started = True
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
