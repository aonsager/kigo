#!/usr/bin/env python3
"""describe_via_claude.py — OPTIONAL turnkey driver for stage 3.

Runs every `batches/batch-*.txt` prompt (from `describe.py emit`) through the
Anthropic Messages API and writes each JSON-array reply to
`responses/batch-*.json`, so the full year's descriptions can be generated
without pasting batches into a chat by hand. `describe.py` stays the
provider-agnostic core; this is a convenience wrapper you can ignore if you
drive a different model.

Requires `ANTHROPIC_API_KEY` in the environment. Stdlib only (raw HTTPS to the
API) — no `anthropic` package needed. Idempotent: batches whose response file
already exists are skipped, so a re-run resumes where an interruption stopped.

Usage (from repo root):
    export ANTHROPIC_API_KEY=sk-ant-...
    python3 scripts/content/fill/describe_via_claude.py \
        --batches scripts/content/fill/batches \
        --responses scripts/content/fill/responses
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API_URL = "https://api.anthropic.com/v1/messages"
API_VERSION = "2023-06-01"
# Latest-generation Claude; override with --model if you prefer another tier.
DEFAULT_MODEL = "claude-sonnet-5"

_JSON_ARRAY_RE = re.compile(r"\[.*\]", re.DOTALL)


def call_claude(prompt, api_key, model, max_tokens, retries=4):
    body = json.dumps(
        {
            "model": model,
            "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}],
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=body,
        headers={
            "x-api-key": api_key,
            "anthropic-version": API_VERSION,
            "content-type": "application/json",
        },
    )
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            return "".join(block.get("text", "") for block in data.get("content", []))
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 529) and attempt < retries - 1:
                backoff = 5 * (attempt + 1)
                print(f"  API {e.code}; backing off {backoff}s…", file=sys.stderr)
                time.sleep(backoff)
                continue
            print(f"  API error {e.code}: {e.read().decode('utf-8', 'replace')}", file=sys.stderr)
            raise


def extract_json_array(text):
    """Claude is asked to return only a JSON array; tolerate incidental prose or
    a ```json fence by extracting the outermost [ ... ]."""
    match = _JSON_ARRAY_RE.search(text)
    if not match:
        raise ValueError("no JSON array found in model reply")
    return json.loads(match.group(0))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--batches", required=True, type=Path)
    parser.add_argument("--responses", required=True, type=Path)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--max-tokens", type=int, default=8000)
    parser.add_argument("--sleep", type=float, default=1.0, help="seconds between batches")
    args = parser.parse_args(argv)

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("error: set ANTHROPIC_API_KEY in the environment", file=sys.stderr)
        return 2

    prompts = sorted(args.batches.glob("batch-*.txt"))
    if not prompts:
        print(f"error: no batch-*.txt in {args.batches} (run `describe.py emit` first)", file=sys.stderr)
        return 1
    args.responses.mkdir(parents=True, exist_ok=True)

    done = 0
    for prompt_path in prompts:
        out_path = args.responses / (prompt_path.stem + ".json")
        if out_path.exists():
            print(f"  skip {prompt_path.name} (response exists)")
            continue
        text = call_claude(prompt_path.read_text(encoding="utf-8"), api_key, args.model, args.max_tokens)
        try:
            arr = extract_json_array(text)
        except (ValueError, json.JSONDecodeError) as e:
            print(f"error: {prompt_path.name} reply did not parse as JSON: {e}", file=sys.stderr)
            return 1
        out_path.write_text(json.dumps(arr, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"  {prompt_path.name} -> {out_path.name} ({len(arr)} rows)")
        done += 1
        time.sleep(args.sleep)

    print(f"wrote {done} new response file(s) to {args.responses}")
    print("next: python3 scripts/content/fill/describe.py ingest "
          f"--responses {args.responses} --out scripts/content/fill/descriptions.csv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
