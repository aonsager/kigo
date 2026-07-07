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
