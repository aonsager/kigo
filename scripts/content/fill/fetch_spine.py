#!/usr/bin/env python3
"""fetch_spine.py — STAGE 1 of the kigo-2026 fill workflow.

Downloads the `brokyo/saijikijs` kigo dataset (pinned to an immutable commit
SHA for reproducibility) and distils it to the *factual* spine fields we are
legally free to ship, writing them to a local pool JSON.

Why only the factual fields (see scripts/content/fill/README.md and ADR 0022):
the dataset aggregates two copyrighted English translations (Higginson/Kondo's
"500 Essential Season Words" and UVA's "Nyūmon Saijiki"), re-declared under The
Unlicense — but that declaration cannot validly clear the upstream translators'
rights. So we harvest ONLY the uncopyrightable traditional facts —

    kanji, kana reading, romaji reading, season, sub-season, category

— and never the source's English `description`/`commentary` prose. Our own
bilingual descriptions are authored later (stage 3, describe.py).

Network: a single HTTPS GET to raw.githubusercontent.com. Stdlib only.

Usage (from repo root):
    python3 scripts/content/fill/fetch_spine.py \
        --out scripts/content/fill/spine_pool.json
"""
import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

# Pinned 2019-06-14 commit — the repo is inactive, so this SHA is stable and
# guarantees byte-reproducible spine data. Bump deliberately, never floatingly.
PINNED_SHA = "7ca6de5cab3bc28eac256d00e67afdac0dfa084b"
SOURCE_URL = f"https://raw.githubusercontent.com/brokyo/saijikijs/{PINNED_SHA}/kigo.json"

# Canonical five saijiki seasons. "new year" is a season of its own in the
# saijiki tradition (not a sub-season of winter), placed at the head of the year.
VALID_SEASONS = ("new year", "spring", "summer", "autumn", "winter")


def _norm(value):
    """Collapse the dataset's embedded newlines / double spaces (e.g.
    'all\\n autumn' -> 'all autumn') and trim."""
    return " ".join((value or "").split())


def fetch_raw(url=SOURCE_URL):
    with urllib.request.urlopen(url, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def distill(raw):
    """Map raw dataset rows to factual spine records, dropping kana-only
    entries (no kanji to display) and any row with an unknown season.

    Returns a list of dicts: {kanji, reading_ja, reading_en, season,
    subseason, category, gloss_en}. De-duplicated by kanji (first occurrence
    wins) so a word never appears on two days.

    `gloss_en` is the source's short English name (e.g. "plum blossom"),
    normalized. It is a SEARCH-ONLY HELPER — used purely as a Pexels query term
    in stage 4 and NEVER written to the shipped manifest (build_csv.py emits
    only the contract columns). A two-or-three-word English name of a seasonal
    thing is a factual label, not the copyrighted descriptive prose we
    deliberately do not reuse.
    """
    seen_kanji = set()
    pool = []
    for row in raw:
        kanji = _norm(row.get("japanese"))
        reading_ja = _norm(row.get("hiragana"))
        reading_en = _norm(row.get("pronunciation"))
        season = _norm(row.get("season")).lower()
        subseason = _norm(row.get("subSeason")).lower()
        category = _norm(row.get("category")).lower()
        # keep only the leading term before any "/" or "(" — a short factual
        # name, not the fuller gloss — as a search hint.
        gloss_en = _norm(re.split(r"[/(]", row.get("description") or "")[0])

        if not kanji or not reading_ja or not reading_en:
            continue  # need a displayable word + both readings
        if season not in VALID_SEASONS:
            continue
        if kanji in seen_kanji:
            continue
        seen_kanji.add(kanji)
        pool.append(
            {
                "kanji": kanji,
                "reading_ja": reading_ja,
                "reading_en": reading_en,
                "season": season,
                "subseason": subseason,
                "category": category,
                "gloss_en": gloss_en,
            }
        )
    return pool


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--out", required=True, type=Path, help="Where to write the distilled spine pool JSON")
    parser.add_argument("--url", default=SOURCE_URL, help="Override source URL (default: pinned saijikijs)")
    args = parser.parse_args(argv)

    try:
        raw = fetch_raw(args.url)
    except Exception as e:  # noqa: BLE001 — surface any network/parse failure plainly
        print(f"error: failed to fetch spine source {args.url}: {e}", file=sys.stderr)
        return 1

    pool = distill(raw)
    if len(pool) < 365:
        print(
            f"error: distilled only {len(pool)} usable kigo (< 365); source may have changed",
            file=sys.stderr,
        )
        return 1

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(pool, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    by_season = {}
    for r in pool:
        by_season[r["season"]] = by_season.get(r["season"], 0) + 1
    print(f"wrote {len(pool)} kigo to {args.out}")
    print("  by season: " + ", ".join(f"{s}={by_season.get(s, 0)}" for s in VALID_SEASONS))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
