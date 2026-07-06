#!/usr/bin/env python3
"""fetch_images.py — STAGE 4 of the kigo-2026 fill workflow.

Assigns each spine row an `image_id` and the six bilingual attribution fields
the manifest requires, sourcing candidate photography from a SINGLE repository
with clean terms of use: **Pexels** (Pexels License — free commercial use,
attribution appreciated, no sign-in required to view). Two modes:

    real (default, needs --api-key)  Query the Pexels search API once per row
        using the kigo's short English name (gloss_en, a search-only helper
        that never ships) or its romaji, take the top portrait result, and
        record the photographer credit + Pexels License. With --download DIR
        it also downloads each chosen JPEG named <image_id>.jpg, ready to
        optimize and re-host at your imageBaseURL (ADR 0022).

    --placeholder (no key)  Fill gate-passing placeholder attribution so the
        rest of the workflow (and the assemble.py validator) can run
        end-to-end before you have a key. Placeholder rows are clearly marked
        "pending" so they are easy to find and replace.

Every image_id is `kigo-MM-DD` (matching the worked example's convention). The
image URL itself is derived later by the app/pipeline as
`imageBaseURL + "/" + image_id + ".jpg"` — there is no per-row URL column.

Pexels free tier: 200 requests/hour, 20,000/month. A full 365-row real run
needs throttling across ~2 hours; --sleep spaces requests (default 0.5s) and
429s are retried with backoff. Stdlib only.

Usage (from repo root):
    # keyless, to unblock the rest of the pipeline:
    python3 scripts/content/fill/fetch_images.py \
        --spine scripts/content/fill/spine-2026.csv \
        --out   scripts/content/fill/images.csv --placeholder

    # real, with a key (get one free at https://www.pexels.com/api/):
    python3 scripts/content/fill/fetch_images.py \
        --spine scripts/content/fill/spine-2026.csv \
        --out   scripts/content/fill/images.csv \
        --api-key "$PEXELS_API_KEY" \
        --download scripts/content/fill/downloads
"""
import argparse
import csv
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PEXELS_SEARCH = "https://api.pexels.com/v1/search"

IMAGE_COLUMNS = (
    "date", "image_id",
    "attribution_title_ja", "attribution_title_en",
    "attribution_credit_ja", "attribution_credit_en",
    "attribution_license_ja", "attribution_license_en",
)

PEXELS_LICENSE_JA = "Pexels ライセンス"
PEXELS_LICENSE_EN = "Pexels License"


def image_id_for(date):
    """'2026-03-21' -> 'kigo-03-21'."""
    _, mm, dd = date.split("-")
    return f"kigo-{mm}-{dd}"


def _read_spine(path):
    return list(csv.DictReader(path.open(encoding="utf-8")))


def _placeholder_row(row):
    kanji = row["kanji"]
    name_en = row.get("gloss_en") or row["reading_en"]
    return {
        "date": row["date"],
        "image_id": image_id_for(row["date"]),
        "attribution_title_ja": kanji,
        "attribution_title_en": name_en,
        "attribution_credit_ja": "画像未選定（要差し替え）",
        "attribution_credit_en": "Pending image selection",
        "attribution_license_ja": "未確定",
        "attribution_license_en": "To be confirmed",
    }


def _pexels_search(query, api_key, sleep, retries=3):
    """Return the top portrait photo dict, or None if nothing matched."""
    params = urllib.parse.urlencode(
        {"query": query, "per_page": 1, "orientation": "portrait", "size": "large"}
    )
    req = urllib.request.Request(f"{PEXELS_SEARCH}?{params}", headers={"Authorization": api_key})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            photos = data.get("photos") or []
            time.sleep(sleep)
            return photos[0] if photos else None
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                backoff = 5 * (attempt + 1)
                print(f"  rate-limited (429); backing off {backoff}s…", file=sys.stderr)
                time.sleep(backoff)
                continue
            raise


def _real_row(row, photo):
    kanji = row["kanji"]
    name_en = row.get("gloss_en") or row["reading_en"]
    photographer = (photo.get("photographer") or "Unknown").strip()
    return {
        "date": row["date"],
        "image_id": image_id_for(row["date"]),
        "attribution_title_ja": kanji,
        "attribution_title_en": name_en,
        "attribution_credit_ja": f"写真: {photographer} / Pexels",
        "attribution_credit_en": f"Photo: {photographer} / Pexels",
        "attribution_license_ja": PEXELS_LICENSE_JA,
        "attribution_license_en": PEXELS_LICENSE_EN,
    }


def _download(photo, dest):
    src = (photo.get("src") or {})
    url = src.get("large2x") or src.get("large") or src.get("original")
    if not url:
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=120) as resp:
        dest.write_bytes(resp.read())
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--spine", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--api-key", help="Pexels API key (omit with --placeholder)")
    parser.add_argument("--placeholder", action="store_true", help="fill gate-passing placeholders, no network")
    parser.add_argument("--download", type=Path, help="also download chosen JPEGs to this dir (real mode)")
    parser.add_argument("--sleep", type=float, default=0.5, help="seconds between Pexels requests")
    args = parser.parse_args(argv)

    if not args.placeholder and not args.api_key:
        print("error: provide --api-key for a real run, or --placeholder to fill placeholders", file=sys.stderr)
        return 2

    rows = _read_spine(args.spine)
    out_rows, missing = [], []

    for row in rows:
        if args.placeholder:
            out_rows.append(_placeholder_row(row))
            continue
        query = (row.get("gloss_en") or row["reading_en"]).strip()
        photo = _pexels_search(query, args.api_key, args.sleep)
        if not photo:
            missing.append((row["date"], query))
            out_rows.append(_placeholder_row(row))  # keep the row gate-valid; flag it below
            continue
        out_rows.append(_real_row(row, photo))
        if args.download:
            ok = _download(photo, args.download / f"{image_id_for(row['date'])}.jpg")
            print(f"  {row['date']} {row['kanji']} <- {query!r}" + ("" if ok else "  (download failed)"))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=IMAGE_COLUMNS)
        writer.writeheader()
        writer.writerows(out_rows)

    mode = "placeholder" if args.placeholder else "Pexels"
    print(f"wrote {len(out_rows)} image rows ({mode}) to {args.out}")
    if missing:
        print(f"  NOTE: {len(missing)} row(s) had no Pexels match and got placeholders — refine and rerun:",
              file=sys.stderr)
        for date, query in missing[:10]:
            print(f"    {date}: no result for {query!r}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
