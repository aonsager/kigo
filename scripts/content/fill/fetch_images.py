#!/usr/bin/env python3
"""fetch_images.py — STAGE 4 of the kigo-2026 fill workflow.

Assigns each spine row an `image_id` and the six bilingual attribution fields
the manifest requires, sourcing candidate photography from TWO providers with
clean terms of use (both free, allow commercial use, and return the
photographer for the credit line):

    pexels    (primary, default) Pexels License — free commercial use,
              attribution appreciated. Free key at https://www.pexels.com/api/ .
    pixabay   (fallback, default) Pixabay License
              (https://pixabay.com/service/license-summary/) — free
              commercial use, no attribution required (we credit anyway).
              Free key at https://pixabay.com/api/docs/ ; 100 requests/minute.

This is a two-phase, human-in-the-loop flow with two subcommands:

    fetch (needs provider keys, unless --placeholder)  Search each spine row
        Japanese-first (kanji, then the English gloss_en, then romaji) across
        both providers, and collect --candidates results round-robin (one per
        search rung) so they span sources — a Pexels kanji match, a Pexels
        gloss match, a Pixabay match — rather than duplicates from one query.
        Each must clear the resolution floor; each is smart-cropped + downscaled
        + JPEG-encoded to <out-images>/<image_id>__cN.jpg, and written to
        `candidates.csv` for human review — so you review the actual image that
        would ship. Also append the Japanese Wikipedia lead image (ja by kanji,
        then en by gloss_en) as a licensed 4th candidate and accuracy
        reference — shippable only when its license is PD/CC0/CC-BY/CC-BY-SA,
        else marked reference-only; disable with --no-wikipedia.

        fetch --placeholder (no key, no network)  Fill gate-passing
        placeholder attribution directly into `images.csv` (via --out) so the
        rest of the workflow (and the assemble.py validator) can run
        end-to-end before you have a key. Placeholder rows are clearly marked
        "pending" so they are easy to find and replace.

    select  After marking exactly one `chosen` cell per date in
        `candidates.csv`, resolves the winners: copies each chosen JPEG to
        the canonical <image_id>.jpg and writes the 8-column `images.csv`
        build_csv.py expects.

The API key is resolved from (in order): --api-key, the matching environment
variable (PIXABAY_API_KEY / PEXELS_API_KEY), or a gitignored `.env` file next
to this script (KEY=VALUE lines). Never pass a key on the command line in a
shared shell — prefer `.env`.

Every image_id is `kigo-MM-DD` (matching the worked example's convention). The
image URL itself is derived later as `imageBaseURL + "/" + image_id + ".jpg"`.

Needs Pillow (`python3 -m pip install Pillow`). Usage (from repo root):
    # keyless, to unblock the rest of the pipeline:
    python3 scripts/content/fill/fetch_images.py fetch \
        --spine scripts/content/fill/spine-2026.csv \
        --out   scripts/content/fill/images.csv --placeholder

    # real: acquire + process candidates (keys read from scripts/content/fill/.env)
    python3 scripts/content/fill/fetch_images.py fetch \
        --spine scripts/content/fill/spine-2026.csv \
        --candidates-out scripts/content/fill/candidates.csv \
        --out-images scripts/content/fill/downloads

    # after marking exactly one 'chosen' cell per date in candidates.csv:
    python3 scripts/content/fill/fetch_images.py select \
        --candidates-in scripts/content/fill/candidates.csv \
        --out scripts/content/fill/images.csv \
        --out-images scripts/content/fill/downloads
"""
import argparse
import csv
import functools
import html
import json
import os
import re
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

# Wikimedia asks API clients to send a descriptive User-Agent with a URL/contact.
WIKI_UA = "kigo-content-pipeline/1.0 (+https://github.com/aonsager/kigo)"


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
    "source_url", "src_w", "src_h", "out_file", "usable", "note",
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

_TAG_RE = re.compile(r"<[^>]+>")


def _strip_html(s):
    """Plain text from an extmetadata HTML value (e.g. Artist)."""
    if not s:
        return ""
    return html.unescape(_TAG_RE.sub("", s)).strip()


def _wiki_license_shippable(license_code, license_short, nonfree):
    """True iff a Wikimedia image may be shipped: not marked non-free and under a
    public-domain / CC0 / CC-BY / CC-BY-SA license. Everything else is
    reference-only. `nonfree` may be a bool or an extmetadata string."""
    if isinstance(nonfree, str):
        nonfree = nonfree.strip().lower() in ("true", "1", "yes")
    if nonfree:
        return False
    code = (license_code or "").strip().lower()
    if code.startswith(("cc0", "pd")):
        return True
    # cc-by / cc-by-sa are fine; NonCommercial (-nc) and NoDerivatives (-nd)
    # variants are not usable for a commercial, cropped app.
    if code.startswith("cc-by") and "-nc" not in code and "-nd" not in code:
        return True
    return "public domain" in (license_short or "").strip().lower()


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
    chosen is blank; title_en falls back to reading_en if gloss_en is empty.
    Stock providers take their static license from PROVIDERS and are always
    usable; other sources (e.g. wikipedia) carry per-image license/usable/note
    on the candidate."""
    prov = cand["provider"]
    if prov in PROVIDERS:
        license_ja = PROVIDERS[prov]["license_ja"]
        license_en = PROVIDERS[prov]["license_en"]
    else:
        license_ja = cand.get("license_ja", "")
        license_en = cand.get("license_en", "")
    return {
        "date": row["date"],
        "image_id": image_id_for(row["date"]),
        "candidate": index,
        "chosen": "",
        "provider": prov,
        "search_term": cand["search_term"],
        "search_lang": cand["search_lang"],
        "photographer": cand["photographer"],
        "license_ja": license_ja,
        "license_en": license_en,
        "title_ja": row["kanji"],
        "title_en": row.get("gloss_en") or row["reading_en"],
        "source_url": cand.get("source_url", ""),
        "src_w": src_w,
        "src_h": src_h,
        "out_file": out_file,
        "usable": cand.get("usable", "yes"),
        "note": cand.get("note", ""),
    }


def image_row_from_candidate(cand_row):
    """Builds an 8-col IMAGE_COLUMNS dict from a chosen candidates.csv row.
    Wikipedia credit reads '画像 … / Wikimedia Commons' (the source may be a
    painting or diagram, not a photo); stock providers read '写真 … / <Provider>'."""
    provider = cand_row["provider"]
    photographer = cand_row["photographer"]
    if provider == "wikipedia":
        credit_ja = f"画像: {photographer} / Wikimedia Commons"
        credit_en = f"Image: {photographer} / Wikimedia Commons"
    else:
        label = provider.capitalize()
        credit_ja = f"写真: {photographer} / {label}"
        credit_en = f"Photo: {photographer} / {label}"
    return {
        "date": cand_row["date"],
        "image_id": cand_row["image_id"],
        "attribution_title_ja": cand_row["title_ja"],
        "attribution_title_en": cand_row["title_en"],
        "attribution_credit_ja": credit_ja,
        "attribution_credit_en": credit_en,
        "attribution_license_ja": cand_row["license_ja"],
        "attribution_license_en": cand_row["license_en"],
    }


def select_chosen(cand_rows):
    """Returns the chosen candidate row per date. Raises ValueError (naming the
    offending dates) if any date has zero or >1 non-empty 'chosen' cell, or if a
    chosen row is reference-only (usable == 'no') — a non-shippable image can
    never be selected."""
    by_date = {}
    for cr in cand_rows:
        by_date.setdefault(cr["date"], []).append(cr)
    picked, bad = [], []
    for date in sorted(by_date):
        marked = [cr for cr in by_date[date] if (cr.get("chosen") or "").strip()]
        if len(marked) != 1:
            bad.append(f"{date} (has {len(marked)} chosen)")
            continue
        if (marked[0].get("usable") or "").strip().lower() == "no":
            bad.append(f"{date} (chosen is reference-only, not shippable)")
            continue
        picked.append(marked[0])
    if bad:
        raise ValueError("each date needs exactly one shippable 'chosen' "
                         "candidate; offending: " + ", ".join(bad))
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
    english = (row.get("gloss_en") or "").strip() or (row.get("reading_en") or "").strip()
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
    """Collect up to `want` distinct floor-passing candidates, drawn
    round-robin — one per rung per round — so the results span different
    search rungs (kanji / English gloss / provider) rather than coming all
    from the first rung. Because a provider like Pexels never returns an empty
    result (it substitutes popular photos for unmatched queries), a
    fill-from-the-first-rung walk would make the later rungs unreachable; the
    round-robin surfaces them so the human can compare across sources. Degrades
    to depth (successive results from one rung) when fewer rungs are productive
    than `want`. Each rung is searched at most once, lazily, and only if
    reached. Candidates are tested against downloadable/effective dims."""
    cache = {}

    def rung_candidates(i):
        if i not in cache:
            rung = ladder[i]
            search = search_fns.get(rung["provider"])
            out = []
            if search is not None:
                for cand in search(rung["term"], rung["lang"]):
                    ew, eh = effective_dims(rung["provider"], cand["width"], cand["height"])
                    if not passes_floor(ew, eh, min_width, min_height):
                        continue
                    enriched = dict(cand)
                    enriched.update(provider=rung["provider"], search_term=rung["term"],
                                    search_lang=rung["lang"])
                    out.append(enriched)
            cache[i] = out
        return cache[i]

    collected, seen = [], set()
    pos = [0] * len(ladder)
    made_progress = True
    while len(collected) < want and made_progress:
        made_progress = False
        for i in range(len(ladder)):
            if len(collected) >= want:
                break
            cands = rung_candidates(i)
            while pos[i] < len(cands):
                cand = cands[pos[i]]
                pos[i] += 1
                key = (cand["provider"], cand["photo_id"])
                if key in seen:
                    continue
                seen.add(key)
                collected.append(cand)
                made_progress = True
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


def _parse_pageimages(data):
    """From an action=query&prop=pageimages (formatversion=2) response, return
    {'title','image_url','filename'} for the lead image, or None if the page is
    missing or has no original image."""
    pages = (data.get("query") or {}).get("pages") or []
    if not pages:
        return None
    page = pages[0]
    if page.get("missing"):
        return None
    url = (page.get("original") or {}).get("source")
    fname = page.get("pageimage")
    if not url or not fname:
        return None
    return {"title": page.get("title") or "", "image_url": url, "filename": fname}


def _parse_imageinfo(data):
    """From an action=query&prop=imageinfo (iiprop=extmetadata|url|size,
    formatversion=2) response, return the fields we need (missing -> ''/0/None)."""
    pages = (data.get("query") or {}).get("pages") or []
    ii = ((pages[0].get("imageinfo") if pages else None) or [{}])[0]
    em = ii.get("extmetadata") or {}

    def val(k):
        return (em.get(k) or {}).get("value")

    return {
        "width": int(ii.get("width") or 0),
        "height": int(ii.get("height") or 0),
        "license_short": val("LicenseShortName") or "",
        "license_code": val("License") or "",
        "nonfree": val("NonFree"),
        "artist": val("Artist") or "",
        "license_url": val("LicenseUrl") or "",
        "description_url": ii.get("descriptionurl") or "",
    }


def _wiki_candidate(pageimg, lang, info, min_width, min_height):
    """Assemble a normalized Wikipedia candidate from a parsed pageimages result,
    the wiki `lang`, and a parsed imageinfo result. Sets `usable` and `note`."""
    shippable = _wiki_license_shippable(info["license_code"], info["license_short"],
                                        info["nonfree"])
    big_enough = passes_floor(info["width"], info["height"], min_width, min_height)
    reasons = []
    if not shippable:
        reasons.append("reference-only: non-free license")
    if not big_enough:
        reasons.append("reference-only: below min resolution")
    record = f"article: {pageimg['title']}"
    if info["license_url"]:
        record += f" · license: {info['license_url']}"
    note = record if not reasons else "; ".join(reasons) + " · " + record
    return {
        "provider": "wikipedia",
        "photo_id": pageimg["filename"],
        "photographer": _strip_html(info["artist"]) or "Unknown",
        "download_url": pageimg["image_url"],
        "source_url": info["description_url"],
        "width": info["width"],
        "height": info["height"],
        "search_term": pageimg["title"],
        "search_lang": lang,
        "license_ja": info["license_short"],
        "license_en": info["license_short"],
        "license_url": info["license_url"],
        "usable": "yes" if (shippable and big_enough) else "no",
        "note": note,
    }


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


def _wiki_api(host, params):
    q = urllib.parse.urlencode({**params, "action": "query", "format": "json",
                                "formatversion": "2"})
    with _get(f"https://{host}/w/api.php?{q}", headers={"User-Agent": WIKI_UA}) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _wikipedia_lookup(kanji, gloss_en, min_width, min_height):
    """Return a Wikipedia lead-image candidate for a kigo, or None. Tries the
    kanji on ja.wikipedia (following redirects), then gloss_en on en.wikipedia."""
    attempts = [("ja.wikipedia.org", kanji, "ja")]
    if gloss_en:
        attempts.append(("en.wikipedia.org", gloss_en, "en"))
    for host, term, lang in attempts:
        if not term:
            continue
        pageimg = _parse_pageimages(_wiki_api(host, {
            "titles": term, "redirects": "1",
            "prop": "pageimages", "piprop": "original|name"}))
        if not pageimg:
            continue
        info = _parse_imageinfo(_wiki_api(host, {
            "titles": f"File:{pageimg['filename']}",
            "prop": "imageinfo", "iiprop": "extmetadata|url|size"}))
        return _wiki_candidate(pageimg, lang, info, min_width, min_height)
    return None


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


def _write_csv(path, columns, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=columns)
        w.writeheader()
        w.writerows(rows)


def _download_image(url):
    with _get(url, timeout=120) as resp:
        from io import BytesIO
        return Image.open(BytesIO(resp.read())).convert("RGB")


def _resolve_keys(providers, cli_key):
    keys = {}
    for prov in providers:
        env = PROVIDERS[prov]["env"]
        key = cli_key or os.environ.get(env)
        if key:
            keys[prov] = key
        else:
            print(f"  note: no {prov} key ({env}); its rungs are skipped",
                  file=sys.stderr)
    return keys


def fetch_candidates_for_row(row, search_fns, out_images, *, aspect=(9.0, 19.5),
                             max_edge=2340, jpeg_quality=82, min_width=800,
                             min_height=1200, candidates=3, primary="pexels",
                             fallback="pixabay", use_japanese=True,
                             include_wikipedia=True, download=_download_image,
                             wiki_lookup=_wikipedia_lookup):
    """Acquire + process candidate images for one spine row. Returns
    (candidate_row dicts, error strings). Injecting `download`/`wiki_lookup`
    lets callers run offline; production wires the real network functions."""
    aspect_w, aspect_h = aspect
    errors = []
    ladder = build_ladder(row, primary=primary, fallback=fallback,
                          use_japanese=use_japanese)
    cands = collect_candidates(ladder, search_fns, min_width, min_height, candidates)
    row_out = []
    for i, cand in enumerate(cands, start=1):
        img = process_image(download(cand["download_url"]), aspect_w, aspect_h, max_edge)
        fname = f"{image_id_for(row['date'])}__c{i}.jpg"
        save_jpeg(img, out_images / fname, jpeg_quality)
        row_out.append(candidate_row(row, cand, i, fname, img.width, img.height))
    if include_wikipedia:
        try:
            wiki = wiki_lookup(row["kanji"], row.get("gloss_en") or row["reading_en"],
                               min_width, min_height)
            if wiki:
                idx = len(row_out) + 1
                img = process_image(download(wiki["download_url"]), aspect_w, aspect_h, max_edge)
                fname = f"{image_id_for(row['date'])}__c{idx}.jpg"
                save_jpeg(img, out_images / fname, jpeg_quality)
                row_out.append(candidate_row(row, wiki, idx, fname, img.width, img.height))
        except Exception as e:  # a bonus wiki candidate must not drop the stock ones
            errors.append(f"wikipedia: {e!r}")
    return row_out, errors


def cmd_fetch(args):
    rows = _read_spine(args.spine)
    if args.placeholder:
        _write_csv(args.out, IMAGE_COLUMNS, [_placeholder_row(r) for r in rows])
        print(f"wrote {len(rows)} placeholder image rows to {args.out}")
        return 0

    aspect_w, aspect_h = parse_aspect(args.aspect)
    fallback = None if args.no_fallback else args.fallback
    providers = [args.primary] + ([fallback] if fallback else [])
    keys = _resolve_keys(dict.fromkeys(providers), args.api_key)
    if args.primary not in keys:
        print(f"error: primary provider {args.primary} has no key", file=sys.stderr)
        return 2

    search_fns = {
        prov: functools.partial(_SEARCH[prov], api_key=keys[prov],
                                per_page=args.per_page, sleep=args.sleep)
        for prov in keys
    }

    out_rows, missing, errors = [], [], []
    for row in rows:
        try:
            row_out, row_errors = fetch_candidates_for_row(
                row, search_fns, args.out_images,
                aspect=(aspect_w, aspect_h), max_edge=args.max_edge,
                jpeg_quality=args.jpeg_quality, min_width=args.min_width,
                min_height=args.min_height, candidates=args.candidates,
                primary=args.primary, fallback=fallback,
                use_japanese=not args.no_japanese,
                include_wikipedia=not args.no_wikipedia)
            for msg in row_errors:
                errors.append((row["date"], msg))
                print(f"  {row['date']} {row['kanji']}: {msg}", file=sys.stderr)
            if not row_out:
                missing.append((row["date"], row.get("gloss_en") or row["reading_en"]))
                continue
            out_rows.extend(row_out)
            print(f"  {row['date']} {row['kanji']}: {len(row_out)} candidate(s)")
        except Exception as e:  # one bad row must not discard the whole run
            errors.append((row["date"], repr(e)))
            print(f"  {row['date']} {row['kanji']}: ERROR {e}", file=sys.stderr)
            continue

    _write_csv(args.candidates_out, CANDIDATE_COLUMNS, out_rows)
    print(f"wrote {len(out_rows)} candidate rows to {args.candidates_out}")
    if missing:
        print(f"  NOTE: {len(missing)} row(s) had no candidate — refine and rerun:",
              file=sys.stderr)
        for date, q in missing[:10]:
            print(f"    {date}: no result for {q!r}", file=sys.stderr)
    if errors:
        print(f"  NOTE: {len(errors)} row(s) errored and were skipped:", file=sys.stderr)
        for date, err in errors[:10]:
            print(f"    {date}: {err}", file=sys.stderr)
    return 0


def cmd_select(args):
    cand_rows = list(csv.DictReader(args.candidates_in.open(encoding="utf-8")))
    try:
        picked = select_chosen(cand_rows)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    import shutil
    image_rows = []
    for cr in picked:
        dest = args.out_images / f"{cr['image_id']}.jpg"
        shutil.copyfile(args.out_images / cr["out_file"], dest)
        image_rows.append(image_row_from_candidate(cr))
    _write_csv(args.out, IMAGE_COLUMNS, image_rows)
    print(f"selected {len(image_rows)} image(s) -> {args.out}")
    return 0


def main(argv=None):
    load_dotenv()
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    sub = parser.add_subparsers(dest="cmd", required=True)

    pf = sub.add_parser("fetch", help="acquire + process candidate images")
    pf.add_argument("--spine", required=True, type=Path)
    pf.add_argument("--out", type=Path, help="images.csv (placeholder mode only)")
    pf.add_argument("--candidates-out", type=Path,
                    default=Path("candidates.csv"), dest="candidates_out")
    pf.add_argument("--out-images", type=Path, dest="out_images",
                    default=Path("downloads"))
    pf.add_argument("--placeholder", action="store_true")
    pf.add_argument("--primary", choices=sorted(PROVIDERS), default="pexels")
    pf.add_argument("--fallback", choices=sorted(PROVIDERS), default="pixabay")
    pf.add_argument("--no-fallback", action="store_true")
    pf.add_argument("--no-japanese", action="store_true")
    pf.add_argument("--no-wikipedia", action="store_true")
    pf.add_argument("--candidates", type=int, default=3)
    pf.add_argument("--per-page", type=int, default=10)
    pf.add_argument("--min-width", type=int, default=800)
    pf.add_argument("--min-height", type=int, default=1200)
    pf.add_argument("--aspect", default="9:19.5")
    pf.add_argument("--max-edge", type=int, default=2340, dest="max_edge")
    pf.add_argument("--jpeg-quality", type=int, default=82, dest="jpeg_quality")
    pf.add_argument("--api-key")
    pf.add_argument("--sleep", type=float, default=0.7)
    pf.set_defaults(func=cmd_fetch)

    ps = sub.add_parser("select", help="resolve the human-chosen candidate")
    ps.add_argument("--candidates-in", required=True, type=Path, dest="candidates_in")
    ps.add_argument("--out", required=True, type=Path)
    ps.add_argument("--out-images", required=True, type=Path, dest="out_images")
    ps.set_defaults(func=cmd_select)

    args = parser.parse_args(argv)
    if args.cmd == "fetch" and args.placeholder and not args.out:
        parser.error("--placeholder requires --out")
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
