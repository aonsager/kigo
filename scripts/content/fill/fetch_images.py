#!/usr/bin/env python3
"""fetch_images.py — STAGE 4 of the kigo-2026 fill workflow.

Assigns each spine row an `image_id` and the six bilingual attribution fields
the manifest requires, sourcing candidate photography from a SINGLE repository
with clean terms of use. Two providers are supported (pick one with
`--provider`); both are free, allow commercial use, and return the photographer
for the credit line:

    pixabay   Pixabay License (https://pixabay.com/service/license-summary/) —
              free commercial use, no attribution required (we credit anyway).
              Free key at https://pixabay.com/api/docs/ ; 100 requests/minute.
    pexels    Pexels License — free commercial use, attribution appreciated.
              Free key at https://www.pexels.com/api/ .

Modes:

    real (default, needs a key)  Query the provider once per row using the
        kigo's short English name (gloss_en, a search-only helper that never
        ships) or its romaji, take the top vertical result, and record the
        photographer credit + license. With --download DIR it also downloads
        each chosen JPEG named <image_id>.jpg, ready to optimize and re-host at
        your imageBaseURL (ADR 0022).

    --placeholder (no key)  Fill gate-passing placeholder attribution so the
        rest of the workflow (and the assemble.py validator) can run
        end-to-end before you have a key. Placeholder rows are clearly marked
        "pending" so they are easy to find and replace.

The API key is resolved from (in order): --api-key, the matching environment
variable (PIXABAY_API_KEY / PEXELS_API_KEY), or a gitignored `.env` file next
to this script (KEY=VALUE lines). Never pass a key on the command line in a
shared shell — prefer `.env`.

Every image_id is `kigo-MM-DD` (matching the worked example's convention). The
image URL itself is derived later as `imageBaseURL + "/" + image_id + ".jpg"`.

Stdlib only. Usage (from repo root):
    # keyless, to unblock the rest of the pipeline:
    python3 scripts/content/fill/fetch_images.py \
        --spine scripts/content/fill/spine-2026.csv \
        --out   scripts/content/fill/images.csv --placeholder

    # real (key read from scripts/content/fill/.env):
    python3 scripts/content/fill/fetch_images.py \
        --spine scripts/content/fill/spine-2026.csv \
        --out   scripts/content/fill/images.csv \
        --provider pixabay \
        --download scripts/content/fill/downloads
"""
import argparse
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENV_FILE = HERE / ".env"

# Pixabay's image CDN (and some Pexels edges) 403 the default Python-urllib
# User-Agent; send a browser-like one on every request.
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) kigo-content-pipeline/1.0"


def _get(url, headers=None, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    return urllib.request.urlopen(req, timeout=timeout)

IMAGE_COLUMNS = (
    "date", "image_id",
    "attribution_title_ja", "attribution_title_en",
    "attribution_credit_ja", "attribution_credit_en",
    "attribution_license_ja", "attribution_license_en",
)

# Per-provider config: which env var holds the key, the license strings, and
# how to build a request + normalize a hit to {photographer, download_url}.
PROVIDERS = {
    "pixabay": {
        "env": "PIXABAY_API_KEY",
        "license_ja": "Pixabay ライセンス",
        "license_en": "Pixabay License",
    },
    "pexels": {
        "env": "PEXELS_API_KEY",
        "license_ja": "Pexels ライセンス",
        "license_en": "Pexels License",
    },
}


def load_dotenv(path=ENV_FILE):
    """Populate os.environ from a simple KEY=VALUE .env file (does not override
    values already set in the real environment)."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())


def image_id_for(date):
    """'2026-03-21' -> 'kigo-03-21'."""
    _, mm, dd = date.split("-")
    return f"kigo-{mm}-{dd}"


def parse_aspect(text):
    """'9:19.5' -> (9.0, 19.5). Raises ValueError on malformed input."""
    parts = text.split(":")
    if len(parts) != 2:
        raise ValueError(f"aspect must be 'W:H', got {text!r}")
    w, h = float(parts[0]), float(parts[1])
    if w <= 0 or h <= 0:
        raise ValueError(f"aspect components must be positive, got {text!r}")
    return (w, h)


def effective_dims(provider, width, height, cap=1280):
    """Downloadable dimensions. Pexels serves full-res `original`; Pixabay's
    free-tier largeImageURL is capped at `cap` on the long edge."""
    if provider != "pixabay":
        return (width, height)
    long_edge = max(width, height)
    if long_edge <= cap:
        return (width, height)
    scale = cap / long_edge
    return (round(width * scale), round(height * scale))


def passes_floor(width, height, min_width, min_height):
    return width >= min_width and height >= min_height


def _read_spine(path):
    return list(csv.DictReader(path.open(encoding="utf-8")))


# --- Provider search adapters. Each returns a normalized dict or None. --------

def _pixabay_search(query, api_key, sleep, retries=3):
    params = urllib.parse.urlencode({
        "key": api_key, "q": query, "image_type": "photo",
        "orientation": "vertical", "per_page": 3, "safesearch": "true", "lang": "en",
    })
    url = f"https://pixabay.com/api/?{params}"
    for attempt in range(retries):
        try:
            with _get(url) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            time.sleep(sleep)
            hits = data.get("hits") or []
            if not hits:
                return None
            hit = hits[0]
            return {
                "photographer": (hit.get("user") or "Unknown").strip(),
                "download_url": hit.get("largeImageURL") or hit.get("webformatURL"),
            }
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                backoff = 10 * (attempt + 1)
                print(f"  rate-limited (429); backing off {backoff}s…", file=sys.stderr)
                time.sleep(backoff)
                continue
            raise


def _pexels_search(query, api_key, sleep, retries=3):
    params = urllib.parse.urlencode(
        {"query": query, "per_page": 1, "orientation": "portrait", "size": "large"}
    )
    for attempt in range(retries):
        try:
            with _get(f"https://api.pexels.com/v1/search?{params}",
                      headers={"Authorization": api_key}) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            time.sleep(sleep)
            photos = data.get("photos") or []
            if not photos:
                return None
            photo = photos[0]
            src = photo.get("src") or {}
            return {
                "photographer": (photo.get("photographer") or "Unknown").strip(),
                "download_url": src.get("large2x") or src.get("large") or src.get("original"),
            }
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                backoff = 5 * (attempt + 1)
                print(f"  rate-limited (429); backing off {backoff}s…", file=sys.stderr)
                time.sleep(backoff)
                continue
            raise


_SEARCH = {"pixabay": _pixabay_search, "pexels": _pexels_search}


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


def _real_row(row, hit, provider):
    cfg = PROVIDERS[provider]
    kanji = row["kanji"]
    name_en = row.get("gloss_en") or row["reading_en"]
    photographer = hit["photographer"]
    label = provider.capitalize()
    return {
        "date": row["date"],
        "image_id": image_id_for(row["date"]),
        "attribution_title_ja": kanji,
        "attribution_title_en": name_en,
        "attribution_credit_ja": f"写真: {photographer} / {label}",
        "attribution_credit_en": f"Photo: {photographer} / {label}",
        "attribution_license_ja": cfg["license_ja"],
        "attribution_license_en": cfg["license_en"],
    }


def _download(hit, dest):
    url = hit.get("download_url")
    if not url:
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    with _get(url, timeout=120) as resp:
        dest.write_bytes(resp.read())
    return True


def main(argv=None):
    load_dotenv()
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--spine", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--provider", choices=sorted(PROVIDERS), default="pixabay")
    parser.add_argument("--api-key", help="override the key (else env / .env is used)")
    parser.add_argument("--placeholder", action="store_true", help="fill gate-passing placeholders, no network")
    parser.add_argument("--download", type=Path, help="also download chosen JPEGs to this dir (real mode)")
    parser.add_argument("--sleep", type=float, default=0.7, help="seconds between API requests")
    args = parser.parse_args(argv)

    api_key = None
    if not args.placeholder:
        api_key = args.api_key or os.environ.get(PROVIDERS[args.provider]["env"])
        if not api_key:
            env_name = PROVIDERS[args.provider]["env"]
            print(
                f"error: no {args.provider} key — set {env_name} (in the environment or "
                f"scripts/content/fill/.env), pass --api-key, or use --placeholder",
                file=sys.stderr,
            )
            return 2

    search = _SEARCH[args.provider]
    rows = _read_spine(args.spine)
    out_rows, missing = [], []

    for row in rows:
        if args.placeholder:
            out_rows.append(_placeholder_row(row))
            continue
        query = (row.get("gloss_en") or row["reading_en"]).strip()
        hit = search(query, api_key, args.sleep)
        if not hit:
            missing.append((row["date"], query))
            out_rows.append(_placeholder_row(row))  # keep the row gate-valid; flag it below
            continue
        out_rows.append(_real_row(row, hit, args.provider))
        if args.download:
            ok = _download(hit, args.download / f"{image_id_for(row['date'])}.jpg")
            print(f"  {row['date']} {row['kanji']} <- {query!r}" + ("" if ok else "  (download failed)"))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=IMAGE_COLUMNS)
        writer.writeheader()
        writer.writerows(out_rows)

    mode = "placeholder" if args.placeholder else args.provider
    print(f"wrote {len(out_rows)} image rows ({mode}) to {args.out}")
    if missing:
        print(f"  NOTE: {len(missing)} row(s) had no match and got placeholders — refine and rerun:",
              file=sys.stderr)
        for date, query in missing[:10]:
            print(f"    {date}: no result for {query!r}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
