#!/usr/bin/env python3
"""fill.py — the front door to the kigo-2026 content-fill workflow.

Four subcommands over the SQLite editorial review store (store.py):

    spine     seed the 365 day facts from the deterministic spine (assign_dates)
    generate  author prose + fetch image candidates for a date range
    compile   export approved days to content/kigo-2026.csv + run assemble.py
    review    serve the local web review UI

The proven stage scripts stay the engine; this orchestrates them and persists
to the store. "Approved freezes": spine/generate never touch an approved day
(unless --force). Stdlib only (+ Pillow, via fetch_images). See
docs/adr/0025-sqlite-editorial-review-store.md.
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

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
DEFAULT_DB = HERE / "review.db"
DEFAULT_POOL = HERE / "spine_pool.json"
DEFAULT_MANIFEST = REPO_ROOT / "Resources" / "manifest.json"


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

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
