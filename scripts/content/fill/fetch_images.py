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

from PIL import Image

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

CANDIDATE_COLUMNS = (
    "date", "image_id", "candidate", "chosen",
    "provider", "search_term", "search_lang", "photographer",
    "license_ja", "license_en", "title_ja", "title_en",
    "source_url", "src_w", "src_h", "out_file",
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


def candidate_row(row, cand, index, out_file, src_w, src_h):
    """Builds one CANDIDATE_COLUMNS dict from row, candidate, and metadata.
    chosen is left blank; title_en falls back to reading_en if gloss_en is empty."""
    cfg = PROVIDERS[cand["provider"]]
    return {
        "date": row["date"],
        "image_id": image_id_for(row["date"]),
        "candidate": index,
        "chosen": "",
        "provider": cand["provider"],
        "search_term": cand["search_term"],
        "search_lang": cand["search_lang"],
        "photographer": cand["photographer"],
        "license_ja": cfg["license_ja"],
        "license_en": cfg["license_en"],
        "title_ja": row["kanji"],
        "title_en": row.get("gloss_en") or row["reading_en"],
        "source_url": cand.get("source_url", ""),
        "src_w": src_w,
        "src_h": src_h,
        "out_file": out_file,
    }


def image_row_from_candidate(cand_row):
    """Builds an 8-col IMAGE_COLUMNS dict from a chosen candidates.csv row,
    with credit strings in Japanese and English."""
    label = cand_row["provider"].capitalize()
    photographer = cand_row["photographer"]
    return {
        "date": cand_row["date"],
        "image_id": cand_row["image_id"],
        "attribution_title_ja": cand_row["title_ja"],
        "attribution_title_en": cand_row["title_en"],
        "attribution_credit_ja": f"写真: {photographer} / {label}",
        "attribution_credit_en": f"Photo: {photographer} / {label}",
        "attribution_license_ja": cand_row["license_ja"],
        "attribution_license_en": cand_row["license_en"],
    }


def select_chosen(cand_rows):
    """Returns the chosen candidate row per date. Raises ValueError (with
    offending dates) if any date has zero or >1 non-empty 'chosen' cell."""
    by_date = {}
    for cr in cand_rows:
        by_date.setdefault(cr["date"], []).append(cr)
    picked, bad = [], []
    for date in sorted(by_date):
        marked = [cr for cr in by_date[date] if (cr.get("chosen") or "").strip()]
        if len(marked) != 1:
            bad.append(f"{date} (has {len(marked)} chosen)")
            continue
        picked.append(marked[0])
    if bad:
        raise ValueError("each date needs exactly one 'chosen' candidate; "
                         "offending: " + ", ".join(bad))
    return picked


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


# Japanese language code per provider (English is always "en").
_JP_LANG = {"pexels": "ja-JP", "pixabay": "ja"}


def build_ladder(row, primary="pexels", fallback="pixabay", use_japanese=True):
    """Ordered (provider, term, lang) attempts. Empty-term rungs are dropped."""
    kanji = (row.get("kanji") or "").strip()
    english = (row.get("gloss_en") or row.get("reading_en") or "").strip()
    romaji = (row.get("reading_en") or "").strip()

    plan = []
    if primary:
        if use_japanese and kanji:
            plan.append((primary, kanji, _JP_LANG[primary]))
        if english:
            plan.append((primary, english, "en"))
    if fallback:
        if use_japanese and kanji:
            plan.append((fallback, kanji, _JP_LANG[fallback]))
        if english:
            plan.append((fallback, english, "en"))
    if primary and romaji:
        plan.append((primary, romaji, "en"))

    return [{"provider": p, "term": t, "lang": l} for (p, t, l) in plan]


def collect_candidates(ladder, search_fns, min_width, min_height, want):
    """Walk the attempt ladder, keeping distinct candidates that clear the
    resolution floor (tested on downloadable/effective dims), up to `want`."""
    collected, seen = [], set()
    for rung in ladder:
        if len(collected) >= want:
            break
        search = search_fns.get(rung["provider"])
        if search is None:
            continue
        for cand in search(rung["term"], rung["lang"]):
            key = (rung["provider"], cand["photo_id"])
            if key in seen:
                continue
            ew, eh = effective_dims(rung["provider"], cand["width"], cand["height"])
            if not passes_floor(ew, eh, min_width, min_height):
                continue
            seen.add(key)
            enriched = dict(cand)
            enriched.update(provider=rung["provider"], search_term=rung["term"],
                            search_lang=rung["lang"])
            collected.append(enriched)
            if len(collected) >= want:
                break
    return collected


def _read_spine(path):
    return list(csv.DictReader(path.open(encoding="utf-8")))


# --- Provider JSON parsers. Return a list of normalized candidate dicts. --------

def _parse_pexels(data):
    out = []
    for p in (data.get("photos") or []):
        src = p.get("src") or {}
        url = src.get("original") or src.get("large2x") or src.get("large")
        if not url:
            continue
        out.append({
            "photo_id": str(p.get("id")),
            "photographer": (p.get("photographer") or "Unknown").strip(),
            "download_url": url,
            "source_url": p.get("url") or "",
            "width": int(p.get("width") or 0),
            "height": int(p.get("height") or 0),
        })
    return out


def _parse_pixabay(data):
    out = []
    for h in (data.get("hits") or []):
        url = h.get("largeImageURL") or h.get("webformatURL")
        if not url:
            continue
        out.append({
            "photo_id": str(h.get("id")),
            "photographer": (h.get("user") or "Unknown").strip(),
            "download_url": url,
            "source_url": h.get("pageURL") or "",
            "width": int(h.get("imageWidth") or 0),
            "height": int(h.get("imageHeight") or 0),
        })
    return out


# --- Provider search adapters. Fetch JSON and return parser's list. --------

def _pexels_search(term, lang, api_key, per_page, sleep, retries=3):
    q = {"query": term, "per_page": per_page, "orientation": "portrait",
         "size": "large"}
    if "-" in lang:  # Pexels locale expects e.g. "ja-JP"; skip bare "en"
        q["locale"] = lang
    params = urllib.parse.urlencode(q)
    for attempt in range(retries):
        try:
            with _get(f"https://api.pexels.com/v1/search?{params}",
                      headers={"Authorization": api_key}) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            time.sleep(sleep)
            return _parse_pexels(data)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                backoff = 5 * (attempt + 1)
                print(f"  rate-limited (429); backing off {backoff}s…", file=sys.stderr)
                time.sleep(backoff)
                continue
            raise


def _pixabay_search(term, lang, api_key, per_page, sleep, retries=3):
    params = urllib.parse.urlencode(
        {"key": api_key, "q": term, "image_type": "photo", "orientation": "vertical",
         "per_page": max(3, per_page), "safesearch": "true", "lang": lang})
    url = f"https://pixabay.com/api/?{params}"
    for attempt in range(retries):
        try:
            with _get(url) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            time.sleep(sleep)
            return _parse_pixabay(data)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                backoff = 10 * (attempt + 1)
                print(f"  rate-limited (429); backing off {backoff}s…", file=sys.stderr)
                time.sleep(backoff)
                continue
            raise


_SEARCH = {"pixabay": _pixabay_search, "pexels": _pexels_search}


def _flat_data(img):
	"""Flat pixel/palette sequence. get_flattened_data() (Pillow 12+) supersedes
	the deprecated getdata(); fall back to getdata() on older Pillow."""
	getter = getattr(img, "get_flattened_data", None) or img.getdata
	return list(getter())


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


def _trim_split(counts, total_trim):
    """Greedily remove `total_trim` items from the ends of `counts`, always
    dropping the end with the fewer unique colours. Returns (left, right)."""
    lo, hi = 0, len(counts) - 1
    left = right = 0
    for _ in range(total_trim):
        if lo >= hi:
            break
        if counts[lo] <= counts[hi]:
            lo += 1; left += 1
        else:
            hi -= 1; right += 1
    return (left, right)


def _proxy_counts(img, analysis_edge, axis):
    """Per-column (axis='x') or per-row (axis='y') unique-colour counts on a
    quantized, downscaled proxy of `img`."""
    w, h = img.size
    scale = analysis_edge / max(w, h)
    pw, ph = max(1, round(w * scale)), max(1, round(h * scale))
    proxy = img.convert("RGB").resize((pw, ph)).quantize(colors=16)
    data = _flat_data(proxy)  # palette indices, row-major (ph rows of pw)
    if axis == "x":
        return [len({data[y * pw + x] for y in range(ph)}) for x in range(pw)], pw
    return [len({data[y * pw + x] for x in range(pw)}) for y in range(ph)], ph


def smart_crop(img, aspect_w, aspect_h, analysis_edge=256):
    """Crop `img` to aspect_w:aspect_h, trimming the flatter side more."""
    w, h = img.size
    target = aspect_w / aspect_h  # width / height
    current = w / h
    if abs(current - target) < 1e-6:
        return img
    if current > target:
        # too wide -> trim columns
        target_w = max(1, round(h * target))
        total = w - target_w
        counts, pw = _proxy_counts(img, analysis_edge, "x")
        pleft, _ = _trim_split(counts, round(total * pw / w))
        left = round(pleft / pw * w) if pw else 0
        left = min(left, total)
        return img.crop((left, 0, left + target_w, h))
    # too tall -> trim rows
    target_h = max(1, round(w / target))
    total = h - target_h
    counts, ph = _proxy_counts(img, analysis_edge, "y")
    ptop, _ = _trim_split(counts, round(total * ph / h))
    top = round(ptop / ph * h) if ph else 0
    top = min(top, total)
    return img.crop((0, top, w, top + target_h))


def resize_within(img, max_edge):
    """Downscale so the long edge ≤ max_edge; returns img unchanged if already within (never upscales)."""
    w, h = img.size
    long_edge = max(w, h)
    if long_edge <= max_edge:
        return img
    scale = max_edge / long_edge
    return img.resize((max(1, round(w * scale)), max(1, round(h * scale))))


def process_image(img, aspect_w, aspect_h, max_edge):
    """resize_within then smart_crop (order matters: resize first so crop output is already at target size)."""
    return smart_crop(resize_within(img, max_edge), aspect_w, aspect_h)


def save_jpeg(img, path, quality):
    """Save as JPEG (RGB), quality=quality, optimize=True, no EXIF."""
    path.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(path, format="JPEG", quality=quality, optimize=True)


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
