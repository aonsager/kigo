#!/usr/bin/env python3
"""build_csv.py — STAGE 5 (merge) of the kigo-2026 fill workflow.

Joins the three reviewable intermediates —

    spine-2026.csv    (stage 2: date, kanji, readings, + season helpers)
    descriptions.csv  (stage 3: date, description_ja, description_en)
    images.csv        (stage 4: date, image_id, attribution_*)

— on `date` and writes the final source CSV in the exact 13-column contract
that scripts/content/assemble.py consumes (helper columns like season /
subseason / category / gloss_en are DROPPED here, so they never reach the
manifest). Only dates present in ALL THREE inputs are emitted, so a partial
run (e.g. descriptions for just a seasonal sample) yields a smaller but fully
valid CSV rather than blank cells.

After writing, run the real gate to prove it:

    python3 scripts/content/assemble.py --csv content/kigo-2026.csv --out /tmp/manifest.json

Stdlib only. Usage (from repo root):
    python3 scripts/content/fill/build_csv.py \
        --spine        scripts/content/fill/spine-2026.csv \
        --descriptions scripts/content/fill/descriptions.csv \
        --images       scripts/content/fill/images.csv \
        --out          content/kigo-2026.csv
"""
import argparse
import csv
import sys
from pathlib import Path

# Must match scripts/content/csv_parser.REQUIRED_COLUMNS exactly (order included).
CONTRACT_COLUMNS = (
    "date", "kanji", "reading_ja", "reading_en", "translation_en",
    "description_ja", "description_en", "image_id",
    "attribution_title_ja", "attribution_title_en",
    "attribution_credit_ja", "attribution_credit_en",
    "attribution_license_ja", "attribution_license_en",
)


def _by_date(path):
    return {r["date"]: r for r in csv.DictReader(path.open(encoding="utf-8"))}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--spine", required=True, type=Path)
    parser.add_argument("--descriptions", required=True, type=Path)
    parser.add_argument("--images", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args(argv)

    spine = _by_date(args.spine)
    descriptions = _by_date(args.descriptions)
    images = _by_date(args.images)

    complete = sorted(set(spine) & set(descriptions) & set(images))
    if not complete:
        print("error: no dates present in all three inputs", file=sys.stderr)
        return 1

    out_rows = []
    for date in complete:
        s, d, im = spine[date], descriptions[date], images[date]
        out_rows.append(
            {
                "date": date,
                "kanji": s["kanji"],
                "reading_ja": s["reading_ja"],
                "reading_en": s["reading_en"],
                "translation_en": d["translation_en"],
                "description_ja": d["description_ja"],
                "description_en": d["description_en"],
                "image_id": im["image_id"],
                "attribution_title_ja": im["attribution_title_ja"],
                "attribution_title_en": im["attribution_title_en"],
                "attribution_credit_ja": im["attribution_credit_ja"],
                "attribution_credit_en": im["attribution_credit_en"],
                "attribution_license_ja": im["attribution_license_ja"],
                "attribution_license_en": im["attribution_license_en"],
            }
        )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CONTRACT_COLUMNS)
        writer.writeheader()
        writer.writerows(out_rows)

    total = len(spine)
    print(f"wrote {len(out_rows)}/{total} complete rows to {args.out}")
    if len(out_rows) < total:
        missing_desc = len(set(spine) - set(descriptions))
        missing_img = len(set(spine) - set(images))
        print(f"  ({missing_desc} dates still need descriptions, {missing_img} still need images)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
