#!/usr/bin/env python3
"""fill.py — the front door to the kigo-2026 content-fill workflow.

Four subcommands over the SQLite editorial review store (store.py):

    spine     seed the 365 day facts from the deterministic spine (assign_dates)
    generate  author prose for a date range
    compile   export approved days to content/kigo-2026.csv + run assemble.py
    review    serve the local web review UI

The proven stage scripts stay the engine; this orchestrates them and persists
to the store. "Approved freezes": spine/generate never touch an approved day
(unless --force). Stdlib only. See docs/adr/0025-sqlite-editorial-review-store.md.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import assign_dates  # noqa: E402
import describe  # noqa: E402
import describe_via_claude  # noqa: E402
import store  # noqa: E402
import functools  # noqa: E402
import os  # noqa: E402
import csv  # noqa: E402
import subprocess  # noqa: E402
import build_csv  # noqa: E402
import webapp  # noqa: E402

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
DEFAULT_DB = HERE / "review.db"
DEFAULT_POOL = HERE / "spine_pool.json"
DEFAULT_MANIFEST = REPO_ROOT / "Resources" / "manifest.json"
ENV_FILE = HERE / ".env"


def load_dotenv(path=ENV_FILE):
    """Populate os.environ from a simple KEY=VALUE .env file (does not override
    values already set in the real environment). Relocated from the removed
    fetch_images module (ADR 0026)."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())


def seed_from_pool(conn, pool, manifest, new_year_days=7, force=False):
    starts = assign_dates.season_starts(manifest)
    records = assign_dates.assign(pool, starts, new_year_days)
    return store.seed_days(conn, records, force=force)


def generate_descriptions(conn, dates, call_llm, batch_size=20):
    """Author prose for `dates` (day dicts) via call_llm(prompt)->text, validate,
    and store. Returns (written, errors). Nothing is written for a batch until
    its whole reply validates, mirroring describe.py's ingest gate."""
    written, errors = 0, []
    rows = [dict(d) for d in dates]
    for i in range(0, len(rows), batch_size):
        batch = rows[i:i + batch_size]
        payload = describe._batch_payload(batch)
        prompt = describe.PROMPT_PREAMBLE + json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
        try:
            arr = describe_via_claude.extract_json_array(call_llm(prompt))
        except (ValueError, json.JSONDecodeError) as e:
            errors.append(f"batch {i // batch_size}: reply did not parse: {e}")
            continue
        by_date = {obj.get("date"): obj for obj in arr}
        validated = []
        batch_errors = []
        for row in batch:
            date = row["date"]
            obj = by_date.get(date, {})
            tr = (obj.get("translation_en") or "").strip()
            ja = (obj.get("description_ja") or "").strip()
            en = (obj.get("description_en") or "").strip()
            if not tr:
                batch_errors.append(f"{date}: translation_en empty")
            if not ja:
                batch_errors.append(f"{date}: description_ja empty")
            if not en:
                batch_errors.append(f"{date}: description_en empty")
            if describe.DATE_STAMP_RE.search(ja + en):
                batch_errors.append(f"{date}: description contains a forbidden date stamp")
            validated.append((date, tr, ja, en))
        errors.extend(batch_errors)
        if batch_errors:
            continue
        for date, tr, ja, en in validated:
            store.set_day_fields(conn, date, translation_en=tr,
                                 description_ja=ja, description_en=en)
            written += 1
    return written, errors


def _select_days(conn, date_from, date_to, force):
    status = None if force else "unapproved"
    return store.list_days(conn, date_from, date_to, status=status)


def cmd_generate(args):
    # Load the gitignored .env so ANTHROPIC_API_KEY can live there; setdefault
    # means a real exported env var still wins over the file.
    load_dotenv()
    conn = store.connect(args.db)
    days = _select_days(conn, args.date_from, args.date_to, args.force)
    if not days:
        print("no days to generate in range (all approved? run with --force)",
              file=sys.stderr)
        return 1
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("error: set ANTHROPIC_API_KEY (in .env or the environment)", file=sys.stderr)
        return 2
    call_llm = functools.partial(describe_via_claude.call_claude, api_key=api_key,
                                 model=args.model, max_tokens=8000)
    written, errors = generate_descriptions(conn, days, call_llm)
    print(f"descriptions: wrote {written} day(s)")
    for e in errors:
        print("  " + e, file=sys.stderr)
    return 0


def write_contract_csv(rows, out_csv):
    """Write the exact 7-column contract CSV (build_csv.CONTRACT_COLUMNS) from
    store.export_rows output. Returns row count."""
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=build_csv.CONTRACT_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    return len(rows)


def cmd_compile(args):
    conn = store.connect(args.db)
    rows = store.export_rows(conn, args.date_from, args.date_to)
    if not rows:
        print("error: no approved, prose-complete days in range", file=sys.stderr)
        return 1
    n = write_contract_csv(rows, args.out_csv)
    print(f"wrote {n} approved row(s) to {args.out_csv}")
    pending = store.pending_dates(conn, args.date_from, args.date_to)
    if pending:
        print(f"  skipped {len(pending)} unapproved/incomplete day(s) in range", file=sys.stderr)
    assemble = REPO_ROOT / "scripts" / "content" / "assemble.py"
    cmd = [sys.executable, str(assemble), "--csv", str(args.out_csv),
           "--out", str(args.manifest_out)]
    return subprocess.run(cmd).returncode


def cmd_review(args):
    conn = store.connect(args.db)
    srv = webapp.make_server(conn, HERE / "web", host=args.host, port=args.port)
    host, port = srv.server_address
    print(f"review UI on http://{host}:{port}  (Ctrl-C to stop)")
    if host == "0.0.0.0":
        print(f"  bound to all interfaces — reachable on your LAN at http://<this-machine-ip>:{port}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    return 0


def cmd_spine(args):
    conn = store.connect(args.db)
    pool = json.loads(args.pool.read_text(encoding="utf-8"))
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    seeded, skipped = seed_from_pool(conn, pool, manifest, args.new_year_days, args.force)
    print(f"seeded {seeded} day(s); skipped {skipped} approved day(s)")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("spine", help="seed day facts from the deterministic spine")
    p.add_argument("--db", type=Path, default=DEFAULT_DB)
    p.add_argument("--pool", type=Path, default=DEFAULT_POOL)
    p.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    p.add_argument("--new-year-days", type=int, default=7, dest="new_year_days")
    p.add_argument("--force", action="store_true", help="overwrite approved days too")
    p.set_defaults(func=cmd_spine)

    g = sub.add_parser("generate", help="author prose for a date range")
    g.add_argument("--db", type=Path, default=DEFAULT_DB)
    g.add_argument("--from", dest="date_from", required=True)
    g.add_argument("--to", dest="date_to", required=True)
    g.add_argument("--force", action="store_true", help="include approved days too")
    g.add_argument("--model", default=describe_via_claude.DEFAULT_MODEL)
    g.set_defaults(func=cmd_generate)

    c = sub.add_parser("compile", help="export approved days + run assemble.py")
    c.add_argument("--db", type=Path, default=DEFAULT_DB)
    c.add_argument("--from", dest="date_from", default=None)
    c.add_argument("--to", dest="date_to", default=None)
    c.add_argument("--out-csv", type=Path, dest="out_csv",
                   default=REPO_ROOT / "content" / "kigo-2026.csv")
    c.add_argument("--manifest-out", type=Path, dest="manifest_out",
                   default=REPO_ROOT / "Resources" / "manifest.json")
    c.set_defaults(func=cmd_compile)

    r = sub.add_parser("review", help="serve the local web review UI")
    r.add_argument("--db", type=Path, default=DEFAULT_DB)
    r.add_argument("--host", default="0.0.0.0",
                   help="bind address (default 0.0.0.0 — all interfaces; use 127.0.0.1 for local-only)")
    r.add_argument("--port", type=int, default=8000)
    r.set_defaults(func=cmd_review)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
