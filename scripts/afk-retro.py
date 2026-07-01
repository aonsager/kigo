#!/usr/bin/env python3
"""Read-only retrospective analyzer for the afk- loop.

Parses three layers and prints a speed/cost/token summary:
  1. .afk/wrapper.log   -> per-iteration cost + wall-clock + phase (the ledger)
  2. .afk/journal.md    -> per-step result taxonomy (where waste happens)
  3. ~/.claude/projects/<slug>/*.jsonl (+ subagents/) -> token & cache breakdown

Nothing here writes to loop state; safe to run while the loop is live.
"""
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from statistics import median

REPO = Path(__file__).resolve().parent.parent
WRAPPER = REPO / ".afk" / "wrapper.log"
JOURNAL = REPO / ".afk" / "journal.md"
PROJ = Path.home() / ".claude" / "projects" / "-Users-aonsager-projects-kigo"

TS = re.compile(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)")


def parse_ts(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%S%z").replace(tzinfo=timezone.utc)


# ---------- Layer 1: wrapper.log ledger ----------
def parse_wrapper():
    """Return list of iteration dicts. A new 'iteration 1 starting (total $0'
    marks a new loop *run*."""
    iters = []
    run = 0
    pending = {}  # iter_num -> start_ts
    bg600 = 0
    start_re = re.compile(r"iteration (\d+) starting \(total \$([\d.]+)")
    done_re = re.compile(
        r"iteration (\d+) done \| cost \$([\d.]+) \| total \$([\d.]+) \| (.*)$"
    )
    # tolerant: phase= may appear with or without a following result=/met=
    phase_re = re.compile(r"phase=(\w+)")
    result_re = re.compile(r"result=([\w-]+)")
    met_re = re.compile(r"met=(\d+)/(\d+)")
    for line in WRAPPER.read_text(errors="replace").splitlines():
        if "Background tasks still running after 600s" in line:
            bg600 += 1
            continue
        tsm = TS.search(line)
        if not tsm:
            continue
        ts = tsm.group(1)
        sm = start_re.search(line)
        if sm:
            n = int(sm.group(1))
            if n == 1 and sm.group(2) == "0":
                run += 1
            pending[n] = (run, ts)
            continue
        dm = done_re.search(line)
        if dm:
            n = int(dm.group(1))
            r, start = pending.get(n, (run, ts))
            dur = (parse_ts(ts) - parse_ts(start)).total_seconds()
            status = dm.group(4)
            pm = phase_re.search(status)
            rm = result_re.search(status)
            mm = met_re.search(status)
            if pm:
                phase = pm.group(1)
            else:
                # free-text done line = iteration ended without a phase transition.
                # classify the reason so the biggest bucket isn't opaque.
                low = status.lower()
                if "wait" in low or "background" in low or "resume" in low or \
                   "fallback" in low or "implementer" in low or "regression" in low:
                    phase = "(no-transition:waiting)"
                elif "?" in status or "may i" in low or "permission" in low or \
                     "force-delete" in low:
                    phase = "(no-transition:human-stall)"
                else:
                    phase = "(no-transition:other)"
            iters.append(
                {
                    "run": r,
                    "iter": n,
                    "start": start,
                    "done": ts,
                    "dur_s": dur,
                    "cost": float(dm.group(2)),
                    "phase": phase,
                    "result": rm.group(1) if rm else ("no-transition" if not pm else "?"),
                    "met": f"{mm.group(1)}/{mm.group(2)}" if mm else "?",
                    "status": status,
                }
            )
    return iters, bg600


# ---------- Layer 2: journal taxonomy ----------
def parse_journal():
    rows = []
    if not JOURNAL.exists():
        return rows
    for line in JOURNAL.read_text(errors="replace").splitlines():
        parts = [p.strip() for p in line.split("|")]
        if len(parts) >= 5 and TS.match(parts[0]):
            rows.append(
                {
                    "ts": parts[0],
                    "phase": parts[1],
                    "issue": parts[2],
                    "result": parts[3],
                    "met": parts[4],
                    "note": parts[5] if len(parts) > 5 else "",
                }
            )
    return rows


# ---------- Layer 3: jsonl token usage ----------
def sum_usage_file(path):
    tot = defaultdict(int)
    msgs = 0
    first = last = None
    try:
        for line in path.read_text(errors="replace").splitlines():
            if '"usage"' not in line:
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            # usage can be nested under content->message->usage or content->usage
            u = find_usage(d)
            if not u:
                continue
            ts = d.get("timestamp")
            if ts:
                first = first or ts
                last = ts
            for k in (
                "input_tokens",
                "output_tokens",
                "cache_creation_input_tokens",
                "cache_read_input_tokens",
            ):
                tot[k] += u.get(k, 0) or 0
            msgs += 1
    except Exception as e:
        print(f"  ! {path.name}: {e}", file=sys.stderr)
    return tot, msgs, first, last


def find_usage(obj):
    if isinstance(obj, dict):
        if "usage" in obj and isinstance(obj["usage"], dict) and "input_tokens" in obj["usage"]:
            return obj["usage"]
        for v in obj.values():
            r = find_usage(v)
            if r:
                return r
    elif isinstance(obj, list):
        for v in obj:
            r = find_usage(v)
            if r:
                return r
    return None


def token_dive():
    sessions = {}
    for jf in sorted(PROJ.glob("*.jsonl")):
        sid = jf.stem
        tot, msgs, first, last = sum_usage_file(jf)
        subdir = PROJ / sid / "subagents"
        sub_tot = defaultdict(int)
        sub_files = 0
        if subdir.is_dir():
            for sf in subdir.glob("agent-*.jsonl"):
                st, sm, _, _ = sum_usage_file(sf)
                sub_files += 1
                for k, v in st.items():
                    sub_tot[k] += v
        sessions[sid] = {
            "orch": tot,
            "orch_msgs": msgs,
            "sub": sub_tot,
            "sub_files": sub_files,
            "first": first,
            "last": last,
            "mtime": jf.stat().st_mtime,
        }
    return sessions


def fmt_tok(n):
    return f"{n/1e6:.2f}M" if n >= 1e6 else f"{n/1e3:.1f}k"


def main():
    iters, bg600 = parse_wrapper()
    journal = parse_journal()
    print("=" * 72)
    print("LAYER 1 — wrapper.log ledger")
    print("=" * 72)
    runs = sorted({i["run"] for i in iters})
    print(f"runs: {len(runs)}   iterations: {len(iters)}   "
          f"total cost: ${sum(i['cost'] for i in iters):.2f}")
    print(f"'600s background still running' terminations: {bg600}\n")

    # per-phase rollup
    byphase = defaultdict(lambda: {"n": 0, "cost": 0.0, "durs": []})
    for i in iters:
        p = byphase[i["phase"]]
        p["n"] += 1
        p["cost"] += i["cost"]
        p["durs"].append(i["dur_s"])
    print(f"{'phase':<12}{'n':>4}{'cost$':>10}{'$/it':>8}{'med_min':>9}{'p90_min':>9}")
    for ph, d in sorted(byphase.items(), key=lambda x: -x[1]["cost"]):
        durs = sorted(d["durs"])
        med = median(durs) / 60
        p90 = durs[int(len(durs) * 0.9)] / 60 if durs else 0
        print(f"{ph:<12}{d['n']:>4}{d['cost']:>10.2f}{d['cost']/d['n']:>8.2f}"
              f"{med:>9.1f}{p90:>9.1f}")

    print("\n" + "=" * 72)
    print("LAYER 2 — journal.md result taxonomy")
    print("=" * 72)
    byres = defaultdict(int)
    for r in journal:
        # normalize result token (strip parenthetical detail)
        res = r["result"].split("(")[0].strip()
        byres[res] += 1
    for res, n in sorted(byres.items(), key=lambda x: -x[1]):
        print(f"  {n:>3}  {res}")
    waste_kinds = ("bounce", "blocked", "slice-critic-exhausted", "reaped-orphan",
                   "rescoped")
    waste = [r for r in journal if r["result"].split("(")[0].strip() in waste_kinds]
    print(f"\n  waste-ish steps ({len(waste)}):")
    for r in waste:
        print(f"    {r['ts']} {r['phase']:<9} {r['issue']:<6} {r['result']}")

    print("\n" + "=" * 72)
    print("LAYER 3 — jsonl token & cache breakdown")
    print("=" * 72)
    if not PROJ.is_dir():
        print("  (projects dir not found)")
        return
    sessions = token_dive()
    grand = defaultdict(int)
    sub_grand = defaultdict(int)
    for s in sessions.values():
        for k, v in s["orch"].items():
            grand[k] += v
        for k, v in s["sub"].items():
            sub_grand[k] += v
    def report(label, t):
        inp = t["input_tokens"]
        cc = t["cache_creation_input_tokens"]
        cr = t["cache_read_input_tokens"]
        out = t["output_tokens"]
        total_in = inp + cc + cr
        hit = cr / total_in * 100 if total_in else 0
        print(f"  {label}")
        print(f"    input(uncached)={fmt_tok(inp)}  cache_create={fmt_tok(cc)}  "
              f"cache_read={fmt_tok(cr)}  output={fmt_tok(out)}")
        print(f"    cache-hit ratio (read / all-input) = {hit:.1f}%")
    print(f"  sessions parsed: {len(sessions)}")
    report("ORCHESTRATOR (per-iteration afk-step sessions):", grand)
    report("SUBAGENTS (implementer/reviewer/judge worktree work):", sub_grand)
    combined = defaultdict(int)
    for k in set(grand) | set(sub_grand):
        combined[k] = grand[k] + sub_grand[k]
    report("COMBINED:", combined)
    # heaviest sessions
    def sess_out(s):
        return s["orch"]["output_tokens"] + s["sub"]["output_tokens"]
    heavy = sorted(sessions.items(), key=lambda x: -sess_out(x[1]))[:10]
    print("\n  heaviest 10 sessions by output tokens (proxy for reasoning cost):")
    for sid, s in heavy:
        o = s["orch"]["output_tokens"]
        so = s["sub"]["output_tokens"]
        print(f"    {sid[:8]}  orch_out={fmt_tok(o)}  sub_out={fmt_tok(so)}  "
              f"subfiles={s['sub_files']}  {s['last'] or ''}")


if __name__ == "__main__":
    main()
