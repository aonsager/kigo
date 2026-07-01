"""MANUAL calibration lane for the slice arbiter — NON-GATING.
Dispatches the real opus arbiter prompt against a captured fixture and prints
its verdict next to the expected one. Live-model + nondeterministic: never run
this on a CI/headless gating path (global CLAUDE.md testing rule).

Usage: python3 scripts/afk-arbiter-calibrate.py [prd-162 ...]   (default: all)
"""
import json
import subprocess
import sys
from pathlib import Path

FIX = Path(__file__).parent / "arbiter-fixtures"
ARBITER = Path.home() / ".claude/skills/afk-slice/references/arbiter.md"


def build_prompt(fx):
    # arbiter.md holds the instruction; the fixture supplies the artifacts.
    return (
        f"{ARBITER.read_text()}\n\n"
        f"--- PRD BODY ---\n{fx['prd_body']}\n\n"
        f"--- REJECTION HISTORY ---\n{fx['rejection_history']}\n"
    )


def run(fx):
    out = subprocess.run(
        ["claude", "-p", build_prompt(fx), "--model", "opus",
         "--output-format", "json"],
        capture_output=True, text=True, timeout=300,
    ).stdout
    # extract the arbiter's JSON verdict from the CLI json envelope
    try:
        txt = json.loads(out).get("result", out)
    except json.JSONDecodeError:
        txt = out
    start, end = txt.find("{"), txt.rfind("}")
    return json.loads(txt[start:end + 1])


def main(names):
    files = ([FIX / f"{n}.json" for n in names] if names
             else sorted(FIX.glob("prd-*.json")))
    for p in files:
        fx = json.loads(p.read_text())
        v = run(fx)
        exp = fx["expected"]
        match = (v.get("diagnosis") == exp["diagnosis"]
                 and v.get("verdict") == exp["verdict"])
        print(f"PRD {fx['prd']}: expected={exp} actual="
              f"{{'diagnosis': {v.get('diagnosis')!r}, 'verdict': {v.get('verdict')!r}}} "
              f"-> {'MATCH' if match else 'MISMATCH'}")


if __name__ == "__main__":
    main(sys.argv[1:])
