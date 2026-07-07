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
import functools  # noqa: E402
import os  # noqa: E402
import fetch_images  # noqa: E402
import csv  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
import build_csv  # noqa: E402
import webapp  # noqa: E402

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


def generate_images(conn, dates, search_fns, out_images, *, download,
                    wiki_lookup=None, include_wikipedia=True, **fetch_opts):
    """For each day: clear existing candidates, fetch fresh ones, store them.
    Returns (candidate rows written, errors). download/wiki_lookup injectable."""
    out_images.mkdir(parents=True, exist_ok=True)
    written, errors = 0, []
    wl = wiki_lookup or fetch_images._wikipedia_lookup
    for day in dates:
        row = {"date": day["date"], "kanji": day["kanji"],
               "gloss_en": day["gloss_en"], "reading_en": day["reading_en"]}
        store.clear_candidates(conn, day["date"])
        try:
            cand_rows, row_errors = fetch_images.fetch_candidates_for_row(
                row, search_fns, out_images, include_wikipedia=include_wikipedia,
                download=download, wiki_lookup=wl, **fetch_opts)
        except Exception as e:
            errors.append(f"{day['date']}: {e!r}")
            continue
        for msg in row_errors:
            errors.append(f"{day['date']}: {msg}")
        for cand in cand_rows:
            store.add_candidate(conn, day["date"], cand)
            written += 1
    return written, errors


def _select_days(conn, date_from, date_to, force):
    status = None if force else "unapproved"
    return store.list_days(conn, date_from, date_to, status=status)


def cmd_generate(args):
    conn = store.connect(args.db)
    days = _select_days(conn, args.date_from, args.date_to, args.force)
    if not days:
        print("no days to generate in range (all approved? run with --force)",
              file=sys.stderr)
        return 1

    if not args.no_descriptions:
        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if not api_key:
            print("error: set ANTHROPIC_API_KEY (or pass --no-descriptions)", file=sys.stderr)
            return 2
        call_llm = functools.partial(describe_via_claude.call_claude, api_key=api_key,
                                     model=args.model, max_tokens=8000)
        written, errors = generate_descriptions(conn, days, call_llm)
        print(f"descriptions: wrote {written} day(s)")
        for e in errors:
            print("  " + e, file=sys.stderr)

    if not args.no_images:
        fetch_images.load_dotenv()
        fallback = None if args.no_fallback else args.fallback
        providers = dict.fromkeys([args.primary] + ([fallback] if fallback else []))
        keys = fetch_images._resolve_keys(providers, None)
        if args.primary not in keys:
            print(f"error: primary provider {args.primary} has no key", file=sys.stderr)
            return 2
        search_fns = {prov: functools.partial(fetch_images._SEARCH[prov],
                                              api_key=keys[prov], per_page=args.per_page,
                                              sleep=args.sleep) for prov in keys}
        written, errors = generate_images(
            conn, days, search_fns, args.out_images,
            download=fetch_images._download_image,
            include_wikipedia=not args.no_wikipedia,
            candidates=args.candidates, min_width=args.min_width,
            min_height=args.min_height, primary=args.primary, fallback=fallback,
            use_japanese=not args.no_japanese)
        print(f"images: wrote {written} candidate row(s)")
        for e in errors[:10]:
            print("  " + e, file=sys.stderr)
    return 0


def write_contract_csv(rows, out_csv, out_images):
    """Copy each chosen JPEG to its canonical <image_id>.jpg and write the exact
    14-column contract CSV build_csv/csv_parser expect. Returns row count."""
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    for r in rows:
        src = out_images / r["_out_file"]
        dest = out_images / f"{r['image_id']}.jpg"
        if src.resolve() != dest.resolve():
            shutil.copyfile(src, dest)
    with out_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=build_csv.CONTRACT_COLUMNS)
        writer.writeheader()
        for r in rows:
            writer.writerow({c: r[c] for c in build_csv.CONTRACT_COLUMNS})
    return len(rows)


def cmd_compile(args):
    conn = store.connect(args.db)
    rows = store.export_rows(conn, args.date_from, args.date_to)
    if not rows:
        print("error: no approved days with a chosen image in range", file=sys.stderr)
        return 1
    n = write_contract_csv(rows, args.out_csv, args.out_images)
    print(f"wrote {n} approved row(s) to {args.out_csv}")
    pending = store.pending_dates(conn, args.date_from, args.date_to)
    if pending:
        print(f"  skipped {len(pending)} unapproved/incomplete day(s) in range", file=sys.stderr)

    assemble = REPO_ROOT / "scripts" / "content" / "assemble.py"
    cmd = [sys.executable, str(assemble), "--csv", str(args.out_csv),
           "--out", str(args.manifest_out)]
    if args.image_base_url:
        cmd += ["--image-base-url", args.image_base_url]
    result = subprocess.run(cmd)
    return result.returncode


def cmd_review(args):
    conn = store.connect(args.db)
    srv = webapp.make_server(conn, HERE / "web", args.images, port=args.port)
    host, port = srv.server_address
    print(f"review UI on http://{host}:{port}  (Ctrl-C to stop)")
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

    g = sub.add_parser("generate", help="author prose + fetch image candidates for a range")
    g.add_argument("--db", type=Path, default=DEFAULT_DB)
    g.add_argument("--from", dest="date_from", required=True)
    g.add_argument("--to", dest="date_to", required=True)
    g.add_argument("--no-descriptions", action="store_true")
    g.add_argument("--no-images", action="store_true")
    g.add_argument("--force", action="store_true", help="include approved days too")
    g.add_argument("--out-images", type=Path, dest="out_images", default=HERE / "downloads")
    g.add_argument("--model", default=describe_via_claude.DEFAULT_MODEL)
    g.add_argument("--primary", choices=sorted(fetch_images.PROVIDERS), default="pexels")
    g.add_argument("--fallback", choices=sorted(fetch_images.PROVIDERS), default="pixabay")
    g.add_argument("--no-fallback", action="store_true")
    g.add_argument("--no-japanese", action="store_true")
    g.add_argument("--no-wikipedia", action="store_true")
    g.add_argument("--candidates", type=int, default=3)
    g.add_argument("--per-page", type=int, default=10, dest="per_page")
    g.add_argument("--min-width", type=int, default=800, dest="min_width")
    g.add_argument("--min-height", type=int, default=1200, dest="min_height")
    g.add_argument("--sleep", type=float, default=0.7)
    g.set_defaults(func=cmd_generate)

    c = sub.add_parser("compile", help="export approved days + run assemble.py")
    c.add_argument("--db", type=Path, default=DEFAULT_DB)
    c.add_argument("--from", dest="date_from", default=None)
    c.add_argument("--to", dest="date_to", default=None)
    c.add_argument("--out-csv", type=Path, dest="out_csv",
                   default=REPO_ROOT / "content" / "kigo-2026.csv")
    c.add_argument("--out-images", type=Path, dest="out_images", default=HERE / "downloads")
    c.add_argument("--manifest-out", type=Path, dest="manifest_out",
                   default=REPO_ROOT / "Resources" / "manifest.json")
    c.add_argument("--image-base-url", dest="image_base_url", default=None)
    c.set_defaults(func=cmd_compile)

    r = sub.add_parser("review", help="serve the local web review UI")
    r.add_argument("--db", type=Path, default=DEFAULT_DB)
    r.add_argument("--port", type=int, default=8000)
    r.add_argument("--images", type=Path, default=HERE / "downloads")
    r.set_defaults(func=cmd_review)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
