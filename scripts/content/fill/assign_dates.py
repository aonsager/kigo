#!/usr/bin/env python3
"""assign_dates.py — STAGE 2 of the kigo-2026 fill workflow.

Deterministically assigns exactly one kigo to each of the 365 days of 2026,
drawing from the factual pool produced by stage 1 (fetch_spine.py) and using
the bundled manifest's Sekki boundaries to decide each day's traditional
season. Output is a reviewable CSV spine (the human-review gate of ADR 0022
reads this before descriptions are drafted).

Placement rules (documented, deterministic, idempotent):

1. **Season of a day** — the 24 Sekki (risshun-anchored, ADR 0015) partition
   the year; the manifest gives each Sekki's start date via its first Kō. The
   Sekki come in seasonal groups of six: spring, summer, autumn, winter. A
   day's season is the group of the Sekki it falls in.
2. **New Year window** — the saijiki "New Year" season has no Sekki; by
   convention it opens the year. Days 01-01 .. 01-07 (the traditional
   matsu-no-uchi first week; --new-year-days to change) are reassigned from
   late winter to "new year".
3. **Progression within a season** — pool kigo are ordered early → mid/all →
   late by sub-season, then spread evenly across that season's days so a word's
   sub-season roughly matches where in the season it lands. Days are ordered by
   distance from the season's start, so winter's Nov→Dec→Jan→Feb wrap reads in
   true seasonal order, not raw calendar order.
4. **No repeats** — the pool is already de-duplicated by kanji, and each kigo is
   used at most once.

Deterministic: same pool + same manifest → byte-identical CSV. Stdlib only.

Usage (from repo root):
    python3 scripts/content/fill/assign_dates.py \
        --pool scripts/content/fill/spine_pool.json \
        --out  scripts/content/fill/spine-2026.csv
"""
import argparse
import csv
import datetime as dt
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_MANIFEST = REPO_ROOT / "Resources" / "manifest.json"

YEAR = 2026
SEASON_ORDER = ("new year", "spring", "summer", "autumn", "winter")
# The 24 Sekki, in manifest order, fall into these four seasonal groups of six.
SEKKI_GROUP_SEASONS = ("spring", "summer", "autumn", "winter")

# Sub-season → progression rank (early first, late last; all-season sits mid so
# it spreads through the middle of the season).
_PHASE_RANKS = (("early", 0.0), ("mid", 1.0), ("all", 1.0), ("late", 2.0))

SPINE_COLUMNS = ("date", "kanji", "reading_ja", "reading_en", "season", "subseason", "category", "gloss_en")


def _mmdd_to_ord(mmdd, year=YEAR):
    m, d = mmdd.split("-")
    return dt.date(year, int(m), int(d)).toordinal()


def season_starts(manifest):
    """Ordinal start date (in 2026) of each of the four Sekki-based seasons,
    derived from the manifest: a season starts at the earliest Kō start of its
    first Sekki."""
    ko = manifest["ko"]
    sekki = manifest["sekki"]
    # earliest Kō start MM-DD per sekkiId
    first_start = {}
    for k in ko:
        sid = k["sekkiId"]
        start = k["dateRange"]["start"]
        if sid not in first_start or start < first_start[sid]:
            first_start[sid] = start
    starts = {}
    for i, s in enumerate(sekki):
        if i % 6 == 0:  # first sekki of each six-sekki season group
            season = SEKKI_GROUP_SEASONS[i // 6]
            starts[season] = _mmdd_to_ord(first_start[s["id"]])
    return starts  # {spring: ord, summer: ord, autumn: ord, winter: ord}


def season_of_day(day_ord, starts):
    """Which of the four Sekki seasons a 2026 date (ordinal) belongs to, using
    the ordered season boundaries with year-end wrap (Jan/early-Feb belong to
    the previous cycle's winter)."""
    bounds = sorted(starts.items(), key=lambda kv: kv[1])  # ascending by start
    current = bounds[-1][0]  # before the first boundary (early Jan) => winter
    for season, start in bounds:
        if day_ord >= start:
            current = season
    return current


def phase_rank(subseason):
    for key, rank in _PHASE_RANKS:
        if key in subseason:
            return rank
    return 1.0  # unlabelled -> treat as mid/spread


def order_pool(kigo):
    """Order a season's kigo early -> mid/all -> late, then by category and
    kanji for a stable, variety-spread sequence."""
    return sorted(kigo, key=lambda k: (phase_rank(k["subseason"]), k["category"], k["kanji"]))


def even_sample(items, n):
    """Pick exactly n items from an ordered list, spread evenly across it,
    preserving order. Requires len(items) >= n."""
    m = len(items)
    return [items[(i * m) // n] for i in range(n)]


def assign(pool, starts, new_year_days):
    """Return an ordered list of {date, kanji, reading_ja, reading_en, season,
    subseason, category} for all 365 days of 2026."""
    all_days = [dt.date(YEAR, 1, 1) + dt.timedelta(days=i) for i in range(365)]
    # New Year window claims the first `new_year_days` days of January.
    ny_cutoff = dt.date(YEAR, 1, 1) + dt.timedelta(days=new_year_days - 1)

    # season -> ordered list of dates (ordered by distance from season start so
    # winter's wrap reads Nov -> Feb, and New Year comes first).
    season_days = {s: [] for s in SEASON_ORDER}
    for day in all_days:
        if day <= ny_cutoff:
            season_days["new year"].append(day)
        else:
            season_days[season_of_day(day.toordinal(), starts)].append(day)

    for season in SEKKI_GROUP_SEASONS:
        start = starts[season]
        season_days[season].sort(key=lambda d: (d.toordinal() - start) % 365)
    # New Year days are already the earliest of January, in calendar order.

    # season -> ordered pool
    pool_by_season = {s: [] for s in SEASON_ORDER}
    for k in pool:
        pool_by_season.setdefault(k["season"], []).append(k)

    records = []
    for season in SEASON_ORDER:
        days = season_days[season]
        if not days:
            continue
        candidates = order_pool(pool_by_season.get(season, []))
        if len(candidates) < len(days):
            raise SystemExit(
                f"error: season '{season}' needs {len(days)} kigo but pool has only {len(candidates)}"
            )
        chosen = even_sample(candidates, len(days))
        for day, kigo in zip(days, chosen):
            records.append(
                {
                    "date": day.isoformat(),
                    "kanji": kigo["kanji"],
                    "reading_ja": kigo["reading_ja"],
                    "reading_en": kigo["reading_en"],
                    "season": season,
                    "subseason": kigo["subseason"] or season,
                    "category": kigo["category"],
                    "gloss_en": kigo.get("gloss_en", ""),
                }
            )

    records.sort(key=lambda r: r["date"])  # emit in calendar order
    return records


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--pool", required=True, type=Path, help="spine_pool.json from fetch_spine.py")
    parser.add_argument("--out", required=True, type=Path, help="Where to write the spine CSV")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST, help="Manifest for Sekki boundaries")
    parser.add_argument("--new-year-days", type=int, default=7, help="How many opening January days get New Year kigo")
    args = parser.parse_args(argv)

    pool = json.loads(args.pool.read_text(encoding="utf-8"))
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    starts = season_starts(manifest)
    records = assign(pool, starts, args.new_year_days)

    if len(records) != 365:
        print(f"error: produced {len(records)} rows, expected 365", file=sys.stderr)
        return 1

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=SPINE_COLUMNS)
        writer.writeheader()
        writer.writerows(records)

    counts = {}
    for r in records:
        counts[r["season"]] = counts.get(r["season"], 0) + 1
    print(f"wrote {len(records)} rows to {args.out}")
    print("  days per season: " + ", ".join(f"{s}={counts.get(s, 0)}" for s in SEASON_ORDER))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
