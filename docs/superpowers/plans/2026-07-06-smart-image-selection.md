# Smart Image Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild stage 4 of the kigo-2026 fill workflow (`fetch_images.py`) into a two-phase, human-in-the-loop image selector: a Japanese-first attempt ladder over two free stock providers, a min-resolution gate, an entropy smart-crop to the phone screen ratio, and 3 fully-processed candidates per day that a human picks from.

**Architecture:** `fetch_images.py` gains two subcommands — `fetch` (walk the ladder, collect up to 3 distinct floor-passing candidates, download + crop + resize + encode each, emit `candidates.csv`) and `select` (read the human-marked `chosen` column, validate one-per-date, emit the existing 8-column `images.csv` + the canonical `<image_id>.jpg`). All decision logic is factored into pure, importable functions; network calls are thin wrappers around pure JSON parsers. `--placeholder` stays a mode of `fetch` and writes `images.csv` directly.

**Tech Stack:** Python 3 stdlib + **Pillow** (already installed, 12.1.1) for the image stage only. Tests use stdlib `assert` in `test_*()` functions run directly (no pytest, no unittest classes) — matching `scripts/content/test_pipeline.py`.

## Global Constraints

- **Test convention:** stdlib only, no pytest/unittest classes. Test file ends with the discovery runner `if __name__ == "__main__": fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]; ...` copied verbatim from `scripts/content/test_pipeline.py`. Run with `python3 scripts/content/fill/test_fetch_images.py`; success is the final line `ALL PASS`.
- **Pillow is the only third-party dependency**, scoped to `fetch_images.py` and its test. Every other fill-workflow script stays stdlib-only.
- **No network in tests.** Provider searches are injected as stub callables; image bytes are synthesized in-memory with Pillow. Network wrappers (`_pexels_search` / `_pixabay_search`) are NOT unit-tested (correct by inspection).
- **Canonical image name:** `kigo-MM-DD.jpg` (from `image_id_for(date)`), matching the manifest's `imageBaseURL + "/" + image_id + ".jpg"` convention (ADR 0022). Candidate files: `kigo-MM-DD__cN.jpg`, N = 1..candidates.
- **`images.csv` schema is frozen** — the 8 `IMAGE_COLUMNS` `csv_parser.py` / `build_csv.py` already expect: `date, image_id, attribution_title_ja, attribution_title_en, attribution_credit_ja, attribution_credit_en, attribution_license_ja, attribution_license_en`. `select` and `--placeholder` both emit exactly these.
- **Spine columns available per row:** `date, kanji, reading_ja, reading_en, season, subseason, category, gloss_en` (`reading_en` = romaji; `gloss_en` = English search helper, never shipped).
- **Provider defaults:** `--primary pexels`, `--fallback pixabay`. Pixabay free-tier `largeImageURL` is capped at 1280px long edge; the resolution floor is tested against that effective size, and output **never upscales**.
- Preserve existing behavior: `.env`/env/`--api-key` key resolution, browser-like `USER_AGENT`, `--sleep` throttle + 429 backoff, and the stderr missing-rows report.

---

### Task 1: Pure helpers — aspect parsing, effective dims, resolution floor

**Files:**
- Modify: `scripts/content/fill/fetch_images.py` (add functions near the top, after `image_id_for`)
- Test: `scripts/content/fill/test_fetch_images.py` (create)

**Interfaces:**
- Produces:
  - `parse_aspect(text: str) -> tuple[float, float]` — `"9:19.5"` → `(9.0, 19.5)`; raises `ValueError` on malformed input.
  - `effective_dims(provider: str, width: int, height: int, cap: int = 1280) -> tuple[int, int]` — Pexels returns `(width, height)` unchanged; Pixabay scales down so the long edge is `min(max(width, height), cap)`, preserving aspect (rounded to int).
  - `passes_floor(width: int, height: int, min_width: int, min_height: int) -> bool`.

- [ ] **Step 1: Write the failing test**

Create `scripts/content/fill/test_fetch_images.py`:

```python
"""Deterministic, offline checks for the two-phase image selector
(scripts/content/fill/fetch_images.py). No network, no simulator; Pillow is used
to synthesize test images in-memory. Matches scripts/content/test_pipeline.py.

Run directly:
    python3 scripts/content/fill/test_fetch_images.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_images as fi  # noqa: E402


def test_parse_aspect_handles_decimal():
    assert fi.parse_aspect("9:19.5") == (9.0, 19.5)
    assert fi.parse_aspect("2:3") == (2.0, 3.0)


def test_parse_aspect_rejects_malformed():
    for bad in ("", "9", "9:", "9:0", "a:b", "9:19:5"):
        try:
            fi.parse_aspect(bad)
        except ValueError:
            continue
        raise AssertionError(f"expected ValueError for {bad!r}")


def test_effective_dims_pexels_is_identity():
    assert fi.effective_dims("pexels", 4000, 6000) == (4000, 6000)


def test_effective_dims_pixabay_caps_long_edge_at_1280():
    # 4000x6000 portrait -> long edge (6000) scaled to 1280 -> ~853x1280
    w, h = fi.effective_dims("pixabay", 4000, 6000)
    assert h == 1280
    assert w == 853


def test_effective_dims_pixabay_no_upscale_when_small():
    assert fi.effective_dims("pixabay", 800, 1000) == (800, 1000)


def test_passes_floor():
    assert fi.passes_floor(1080, 2340, 800, 1200) is True
    assert fi.passes_floor(700, 2340, 800, 1200) is False
    assert fi.passes_floor(1080, 1100, 800, 1200) is False


if __name__ == "__main__":
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print("ALL PASS")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `AttributeError: module 'fetch_images' has no attribute 'parse_aspect'`.

- [ ] **Step 3: Write minimal implementation**

In `fetch_images.py`, after `image_id_for`:

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS for all six tests; final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: pure helpers for aspect, effective dims, resolution floor"
```

---

### Task 2: Attempt-ladder construction

**Files:**
- Modify: `scripts/content/fill/fetch_images.py`
- Test: `scripts/content/fill/test_fetch_images.py`

**Interfaces:**
- Consumes: spine `row` dict (Task 1 helpers not needed here).
- Produces:
  - `build_ladder(row, primary="pexels", fallback="pixabay", use_japanese=True) -> list[dict]` — ordered rungs, each `{"provider", "term", "lang"}`. Rungs whose `term` is empty/whitespace are dropped. `fallback=None` drops fallback rungs. `use_japanese=False` drops kanji rungs. Lang codes: Pexels Japanese `"ja-JP"`, Pixabay Japanese `"ja"`, English `"en"`.

Ladder order (each rung emitted only if its term is non-empty and its provider is enabled):
1. primary · `kanji` · primary's JP lang
2. primary · `gloss_en` (→ `reading_en` if `gloss_en` empty) · `en`
3. fallback · `kanji` · fallback's JP lang
4. fallback · `gloss_en` (→ `reading_en`) · `en`
5. primary · `reading_en` (romaji) · `en`

- [ ] **Step 1: Write the failing test**

Add to `test_fetch_images.py`:

```python
def _row(kanji="桜", gloss_en="cherry blossom", reading_en="sakura"):
    return {"date": "2026-03-25", "kanji": kanji,
            "gloss_en": gloss_en, "reading_en": reading_en}


def test_ladder_default_order():
    rungs = fi.build_ladder(_row())
    assert rungs == [
        {"provider": "pexels", "term": "桜", "lang": "ja-JP"},
        {"provider": "pexels", "term": "cherry blossom", "lang": "en"},
        {"provider": "pixabay", "term": "桜", "lang": "ja"},
        {"provider": "pixabay", "term": "cherry blossom", "lang": "en"},
        {"provider": "pexels", "term": "sakura", "lang": "en"},
    ]


def test_ladder_no_japanese_drops_kanji_rungs():
    rungs = fi.build_ladder(_row(), use_japanese=False)
    assert all(r["lang"] == "en" for r in rungs)
    assert all(r["term"] != "桜" for r in rungs)
    assert {r["provider"] for r in rungs} == {"pexels", "pixabay"}


def test_ladder_no_fallback_drops_fallback_rungs():
    rungs = fi.build_ladder(_row(), fallback=None)
    assert all(r["provider"] == "pexels" for r in rungs)


def test_ladder_falls_back_to_romaji_when_gloss_empty():
    rungs = fi.build_ladder(_row(gloss_en=""))
    # rung 2 / 4 use reading_en ("sakura") in place of the empty gloss
    en_terms = [r["term"] for r in rungs if r["lang"] == "en"]
    assert en_terms == ["sakura", "sakura", "sakura"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `AttributeError: module 'fetch_images' has no attribute 'build_ladder'`.

- [ ] **Step 3: Write minimal implementation**

In `fetch_images.py`:

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS; final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: Japanese-first attempt-ladder construction"
```

---

### Task 3: Provider JSON parsers → candidate lists

**Files:**
- Modify: `scripts/content/fill/fetch_images.py` (replace the top-1 `_pixabay_search`/`_pexels_search` bodies; add pure parsers)
- Test: `scripts/content/fill/test_fetch_images.py`

**Interfaces:**
- Produces:
  - `_parse_pexels(data: dict) -> list[dict]`
  - `_parse_pixabay(data: dict) -> list[dict]`
  - Each candidate dict: `{"photo_id": str, "photographer": str, "download_url": str, "source_url": str, "width": int, "height": int}`.
- Thin network wrappers `_pexels_search(term, lang, api_key, per_page, sleep, retries=3)` and `_pixabay_search(term, lang, api_key, per_page, sleep, retries=3)` call the corresponding parser after fetching JSON; they return the parser's list (empty on no hits). Not unit-tested.

- [ ] **Step 1: Write the failing test**

Add to `test_fetch_images.py`:

```python
_PEXELS_SAMPLE = {
    "photos": [
        {"id": 101, "width": 4000, "height": 6000, "url": "https://pexels/p/101",
         "photographer": "Aki",
         "src": {"original": "https://img/101.jpg", "large2x": "https://img/101_2x.jpg"}},
        {"id": 102, "width": 3000, "height": 4500, "url": "https://pexels/p/102",
         "photographer": "Bo",
         "src": {"large": "https://img/102_l.jpg"}},
    ]
}

_PIXABAY_SAMPLE = {
    "hits": [
        {"id": 55, "imageWidth": 4000, "imageHeight": 6000, "pageURL": "https://pix/55",
         "user": "Cho", "largeImageURL": "https://img/55_1280.jpg",
         "webformatURL": "https://img/55_web.jpg"},
    ]
}


def test_parse_pexels_prefers_original_then_large2x():
    cands = fi._parse_pexels(_PEXELS_SAMPLE)
    assert cands[0] == {"photo_id": "101", "photographer": "Aki",
                        "download_url": "https://img/101.jpg",
                        "source_url": "https://pexels/p/101",
                        "width": 4000, "height": 6000}
    # second hit has no original -> falls through to 'large'
    assert cands[1]["download_url"] == "https://img/102_l.jpg"


def test_parse_pixabay_uses_largeimageurl():
    cands = fi._parse_pixabay(_PIXABAY_SAMPLE)
    assert cands[0] == {"photo_id": "55", "photographer": "Cho",
                        "download_url": "https://img/55_1280.jpg",
                        "source_url": "https://pix/55",
                        "width": 4000, "height": 6000}


def test_parsers_return_empty_on_no_hits():
    assert fi._parse_pexels({"photos": []}) == []
    assert fi._parse_pixabay({}) == []
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `AttributeError: module 'fetch_images' has no attribute '_parse_pexels'`.

- [ ] **Step 3: Write minimal implementation**

In `fetch_images.py`, add the parsers and rewrite the search wrappers:

```python
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
```

Note: Pixabay requires `per_page >= 3`; the `max(3, per_page)` guard preserves that. Locale note: Pexels ignores an unknown `locale`, so passing `"en"` is harmless.

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS; final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: provider JSON parsers return candidate lists + lang-aware search"
```

---

### Task 4: `collect_candidates` — ladder walk, floor filter, dedupe, accumulate to N

**Files:**
- Modify: `scripts/content/fill/fetch_images.py`
- Test: `scripts/content/fill/test_fetch_images.py`

**Interfaces:**
- Consumes: `build_ladder` (Task 2), `effective_dims`/`passes_floor` (Task 1).
- Produces:
  - `collect_candidates(ladder, search_fns, min_width, min_height, want) -> list[dict]` where `search_fns` is `{provider: callable(term, lang) -> list[candidate]}`. Walks rungs in order; for each returned candidate that clears the floor (tested on `effective_dims(provider, width, height)`), annotates it with `provider`, `search_term`, `search_lang`, and appends — skipping duplicates keyed by `(provider, photo_id)`. Stops once `want` candidates are collected or the ladder is exhausted. Returns the collected list (length 0..want).

- [ ] **Step 1: Write the failing test**

Add to `test_fetch_images.py`:

```python
def _cand(pid, w, h):
    return {"photo_id": str(pid), "photographer": "X",
            "download_url": f"u{pid}", "source_url": f"s{pid}",
            "width": w, "height": h}


def test_collect_walks_rungs_and_stops_at_want():
    ladder = fi.build_ladder(_row())  # pexels(ja), pexels(en), pixabay(ja), ...
    calls = []

    def pexels(term, lang):
        calls.append(("pexels", term, lang))
        return [_cand(1, 4000, 6000), _cand(2, 4000, 6000)]

    def pixabay(term, lang):
        calls.append(("pixabay", term, lang))
        return [_cand(3, 4000, 6000)]

    got = fi.collect_candidates(ladder, {"pexels": pexels, "pixabay": pixabay},
                                min_width=800, min_height=1200, want=3)
    # first pexels rung already yields 2, second pexels rung is called for the 3rd,
    # producing dupes (same ids) -> must reach pixabay for a distinct 3rd.
    ids = [c["photo_id"] for c in got]
    assert ids == ["1", "2", "3"]
    assert got[0]["provider"] == "pexels" and got[0]["search_lang"] == "ja-JP"
    assert got[2]["provider"] == "pixabay"


def test_collect_dedupes_by_provider_and_id():
    ladder = [{"provider": "pexels", "term": "a", "lang": "en"},
              {"provider": "pexels", "term": "b", "lang": "en"}]
    def pexels(term, lang):
        return [_cand(1, 4000, 6000)]  # same id both rungs
    got = fi.collect_candidates(ladder, {"pexels": pexels},
                                min_width=800, min_height=1200, want=3)
    assert len(got) == 1


def test_collect_applies_pixabay_effective_floor():
    # 4000x6000 pixabay -> effective ~853x1280, passes a 800x1200 floor.
    # 1200x1600 pixabay -> effective 960x1280, width 960 >= 800 passes;
    # 900x1000 pixabay -> effective unchanged (small), height 1000 < 1200 FAILS.
    ladder = [{"provider": "pixabay", "term": "a", "lang": "ja"}]
    def pixabay(term, lang):
        return [_cand(9, 900, 1000), _cand(8, 4000, 6000)]
    got = fi.collect_candidates(ladder, {"pixabay": pixabay},
                                min_width=800, min_height=1200, want=3)
    assert [c["photo_id"] for c in got] == ["8"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `AttributeError: module 'fetch_images' has no attribute 'collect_candidates'`.

- [ ] **Step 3: Write minimal implementation**

In `fetch_images.py`:

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS; final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: collect_candidates walks ladder with floor filter + dedupe"
```

---

### Task 5: Smart-crop (entropy edge-trim on a proxy)

**Files:**
- Modify: `scripts/content/fill/fetch_images.py` (add `from PIL import Image` at top)
- Test: `scripts/content/fill/test_fetch_images.py`

**Interfaces:**
- Produces:
  - `_trim_split(counts: list[int], total_trim: int) -> tuple[int, int]` — two-pointer greedy: repeatedly drop the end with the *fewer* unique-colour count; returns `(left_trim, right_trim)` summing to `total_trim`.
  - `smart_crop(img: Image.Image, aspect_w: float, aspect_h: float, analysis_edge: int = 256) -> Image.Image` — crops `img` to the target ratio, trimming the flatter side more. If the image is wider than target, trims columns; if taller, trims rows. Analysis (per-column/row unique-colour counts) runs on a quantized downscaled proxy; the resulting split is applied proportionally to the full-res image.

- [ ] **Step 1: Write the failing test**

Add to `test_fetch_images.py` (top: `from PIL import Image`):

```python
from PIL import Image  # noqa: E402


def _split_image(width, height, busy_side):
    """A W×H image: one side richly multi-coloured, the other flat grey.
    busy_side in {'left','right','top','bottom'}."""
    img = Image.new("RGB", (width, height), (128, 128, 128))
    px = img.load()
    def busy(x, y):
        return ((x * 37 + y * 91) % 256, (x * 13) % 256, (y * 29) % 256)
    for y in range(height):
        for x in range(width):
            if busy_side == "left" and x < width // 2: px[x, y] = busy(x, y)
            if busy_side == "right" and x >= width // 2: px[x, y] = busy(x, y)
            if busy_side == "top" and y < height // 2: px[x, y] = busy(x, y)
            if busy_side == "bottom" and y >= height // 2: px[x, y] = busy(x, y)
    return img


def test_trim_split_drops_flatter_end():
    # counts: left end flat (1), right end busy (9) -> trim comes off the left.
    left, right = fi._trim_split([1, 1, 5, 9, 9], total_trim=2)
    assert (left, right) == (2, 0)


def test_smart_crop_reaches_target_ratio_trimming_columns():
    img = _split_image(600, 900, busy_side="right")  # wider than 9:19.5
    out = fi.smart_crop(img, 9, 19.5)
    ratio = out.width / out.height
    assert abs(ratio - (9 / 19.5)) < 0.02
    assert out.height == 900  # columns trimmed, height preserved


def test_smart_crop_keeps_the_busy_side():
    # busy on the right -> the flat left columns should be trimmed away, so the
    # cropped region's mean colour differs clearly from the original left edge.
    img = _split_image(600, 900, busy_side="right")
    out = fi.smart_crop(img, 9, 19.5)
    # the far-left column of the crop should NOT be the flat grey band
    left_col = [out.getpixel((0, y)) for y in range(0, 900, 50)]
    assert any(p != (128, 128, 128) for p in left_col)


def test_smart_crop_trims_rows_when_taller_than_target():
    img = _split_image(900, 3000, busy_side="top")  # taller than 9:19.5? 900/3000=0.3 < 0.46
    out = fi.smart_crop(img, 9, 19.5)
    ratio = out.width / out.height
    assert abs(ratio - (9 / 19.5)) < 0.02
    assert out.width == 900  # rows trimmed, width preserved
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `AttributeError: module 'fetch_images' has no attribute '_trim_split'`.

- [ ] **Step 3: Write minimal implementation**

At the top of `fetch_images.py` add `from PIL import Image`. Then:

```python
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
    data = list(proxy.getdata())  # palette indices, row-major (ph rows of pw)
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS; final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: entropy smart-crop (proxy analysis) to target aspect"
```

---

### Task 6: Resize (never upscale) + full processing pipeline

**Files:**
- Modify: `scripts/content/fill/fetch_images.py`
- Test: `scripts/content/fill/test_fetch_images.py`

**Interfaces:**
- Consumes: `smart_crop` (Task 5).
- Produces:
  - `resize_within(img: Image.Image, max_edge: int) -> Image.Image` — downscale so the long edge ≤ `max_edge`; returns `img` unchanged if already within (never upscales).
  - `process_image(img: Image.Image, aspect_w, aspect_h, max_edge) -> Image.Image` — `resize_within` then `smart_crop` (order matters: resize first so crop output is already at target size).
  - `save_jpeg(img: Image.Image, path: Path, quality: int) -> None` — save as JPEG (RGB), `quality=quality`, `optimize=True`, no EXIF.

- [ ] **Step 1: Write the failing test**

Add to `test_fetch_images.py`:

```python
def test_resize_within_downscales_long_edge():
    img = Image.new("RGB", (2000, 4000))
    out = fi.resize_within(img, 2340)
    assert max(out.size) == 2340
    assert out.size == (1170, 2340)


def test_resize_within_never_upscales():
    img = Image.new("RGB", (600, 1280))
    out = fi.resize_within(img, 2340)
    assert out.size == (600, 1280)


def test_process_image_hits_target_ratio_and_max_edge():
    img = _split_image(3000, 4500, busy_side="right")
    out = fi.process_image(img, 9, 19.5, max_edge=2340)
    assert max(out.size) <= 2340
    assert abs(out.width / out.height - 9 / 19.5) < 0.02


def test_save_jpeg_writes_file(tmp_path=None):
    import tempfile
    d = Path(tempfile.mkdtemp())
    p = d / "x.jpg"
    fi.save_jpeg(Image.new("RGB", (100, 200), (10, 20, 30)), p, quality=82)
    assert p.exists() and p.stat().st_size > 0
    assert Image.open(p).size == (100, 200)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `AttributeError: module 'fetch_images' has no attribute 'resize_within'`.

- [ ] **Step 3: Write minimal implementation**

In `fetch_images.py`:

```python
def resize_within(img, max_edge):
    w, h = img.size
    long_edge = max(w, h)
    if long_edge <= max_edge:
        return img
    scale = max_edge / long_edge
    return img.resize((max(1, round(w * scale)), max(1, round(h * scale))))


def process_image(img, aspect_w, aspect_h, max_edge):
    return smart_crop(resize_within(img, max_edge), aspect_w, aspect_h)


def save_jpeg(img, path, quality):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(path, format="JPEG", quality=quality, optimize=True)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS; final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: resize-never-upscale + process_image + JPEG encode"
```

---

### Task 7: `candidates.csv` schema + row building + `select` resolver

**Files:**
- Modify: `scripts/content/fill/fetch_images.py`
- Test: `scripts/content/fill/test_fetch_images.py`

**Interfaces:**
- Consumes: `image_id_for`, `PROVIDERS` (existing license strings), `IMAGE_COLUMNS` (existing).
- Produces:
  - `CANDIDATE_COLUMNS: tuple` = `("date", "image_id", "candidate", "chosen", "provider", "search_term", "search_lang", "photographer", "license_ja", "license_en", "title_ja", "title_en", "source_url", "src_w", "src_h", "out_file")`.
  - `candidate_row(row: dict, cand: dict, index: int, out_file: str, src_w: int, src_h: int) -> dict` — builds one `CANDIDATE_COLUMNS` dict (`chosen=""`, `candidate=index`), `title_ja=row["kanji"]`, `title_en=row.get("gloss_en") or row["reading_en"]`, licenses from `PROVIDERS[cand["provider"]]`.
  - `image_row_from_candidate(cand_row: dict) -> dict` — builds an 8-col `IMAGE_COLUMNS` dict from a chosen `candidates.csv` row: credit `写真: {photographer} / {Provider}` (ja) and `Photo: {photographer} / {Provider}` (en), licenses/titles copied through.
  - `select_chosen(cand_rows: list[dict]) -> list[dict]` — returns the chosen candidate row per date; raises `ValueError` (message listing offending dates) if any date has zero or >1 non-empty `chosen`. A `chosen` cell counts as marked when non-empty after `.strip()`.

- [ ] **Step 1: Write the failing test**

Add to `test_fetch_images.py`:

```python
def _cand_row(date, idx, chosen="", provider="pexels", photographer="Aki"):
    return {"date": date, "image_id": fi.image_id_for(date), "candidate": str(idx),
            "chosen": chosen, "provider": provider, "search_term": "桜",
            "search_lang": "ja-JP", "photographer": photographer,
            "license_ja": "Pexels ライセンス", "license_en": "Pexels License",
            "title_ja": "桜", "title_en": "cherry blossom",
            "source_url": "s", "src_w": "1080", "src_h": "2340",
            "out_file": f"kigo-03-25__c{idx}.jpg"}


def test_candidate_row_shape():
    row = {"date": "2026-03-25", "kanji": "桜", "gloss_en": "cherry blossom",
           "reading_en": "sakura"}
    cand = {"provider": "pexels", "search_term": "桜", "search_lang": "ja-JP",
            "photographer": "Aki", "source_url": "s"}
    out = fi.candidate_row(row, cand, 1, "kigo-03-25__c1.jpg", 1080, 2340)
    assert set(out) == set(fi.CANDIDATE_COLUMNS)
    assert out["chosen"] == "" and out["candidate"] == 1
    assert out["title_ja"] == "桜" and out["title_en"] == "cherry blossom"
    assert out["license_en"] == "Pexels License"


def test_image_row_from_candidate_builds_attribution():
    out = fi.image_row_from_candidate(_cand_row("2026-03-25", 2, chosen="x"))
    assert out["date"] == "2026-03-25"
    assert out["image_id"] == "kigo-03-25"
    assert out["attribution_credit_en"] == "Photo: Aki / Pexels"
    assert out["attribution_credit_ja"] == "写真: Aki / Pexels"
    assert out["attribution_license_en"] == "Pexels License"
    assert set(out) == set(fi.IMAGE_COLUMNS)


def test_select_chosen_requires_exactly_one_per_date():
    rows = [_cand_row("2026-03-25", 1, chosen="x"), _cand_row("2026-03-25", 2)]
    picked = fi.select_chosen(rows)
    assert len(picked) == 1 and picked[0]["candidate"] == "1"


def test_select_chosen_errors_on_zero_or_multiple():
    for rows in (
        [_cand_row("2026-03-25", 1), _cand_row("2026-03-25", 2)],            # zero
        [_cand_row("2026-03-25", 1, "x"), _cand_row("2026-03-25", 2, "x")],  # two
    ):
        try:
            fi.select_chosen(rows)
        except ValueError as e:
            assert "2026-03-25" in str(e)
            continue
        raise AssertionError("expected ValueError")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `AttributeError: module 'fetch_images' has no attribute 'CANDIDATE_COLUMNS'`.

- [ ] **Step 3: Write minimal implementation**

In `fetch_images.py`:

```python
CANDIDATE_COLUMNS = (
    "date", "image_id", "candidate", "chosen",
    "provider", "search_term", "search_lang", "photographer",
    "license_ja", "license_en", "title_ja", "title_en",
    "source_url", "src_w", "src_h", "out_file",
)


def candidate_row(row, cand, index, out_file, src_w, src_h):
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


def image_row_from_candidate(cr):
    label = cr["provider"].capitalize()
    photographer = cr["photographer"]
    return {
        "date": cr["date"],
        "image_id": cr["image_id"],
        "attribution_title_ja": cr["title_ja"],
        "attribution_title_en": cr["title_en"],
        "attribution_credit_ja": f"写真: {photographer} / {label}",
        "attribution_credit_en": f"Photo: {photographer} / {label}",
        "attribution_license_ja": cr["license_ja"],
        "attribution_license_en": cr["license_en"],
    }


def select_chosen(cand_rows):
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS; final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: candidates.csv schema, row building, and select resolver"
```

---

### Task 8: CLI subcommands (`fetch` / `select`) + orchestration + placeholder

**Files:**
- Modify: `scripts/content/fill/fetch_images.py` (replace `main`/argparse with subparsers; add orchestration)
- Test: `scripts/content/fill/test_fetch_images.py` (subprocess-drive the offline paths)

**Interfaces:**
- Consumes: everything above.
- Produces: a `main(argv=None) -> int` with two subcommands. `fetch --placeholder` and `select` are fully offline and tested via subprocess; `fetch` (real) orchestration is exercised only by the offline placeholder path plus inspection (network stays untested per Global Constraints).

Orchestration detail for `fetch` (real): resolve keys for every provider the ladder may use (skip a provider whose key is absent, logging once); for each spine row build the ladder, `collect_candidates` with `functools.partial`-bound search fns, then for each collected candidate download bytes → `Image.open` → `process_image` → `save_jpeg` to `<out-images>/<image_id>__cN.jpg`, capturing the processed image's `size` as `src_w/src_h`, and append `candidate_row(...)`. Write `candidates.csv` (`CANDIDATE_COLUMNS`). Rows with zero candidates go to the stderr missing report.

- [ ] **Step 1: Write the failing test**

Add to `test_fetch_images.py`:

```python
import subprocess, tempfile, csv as _csv

FILL_DIR = Path(__file__).resolve().parent
SCRIPT = FILL_DIR / "fetch_images.py"


def _write_spine(path):
    with path.open("w", newline="", encoding="utf-8") as f:
        w = _csv.DictWriter(f, fieldnames=["date", "kanji", "reading_ja",
                                           "reading_en", "gloss_en"])
        w.writeheader()
        w.writerow({"date": "2026-03-25", "kanji": "桜", "reading_ja": "さくら",
                    "reading_en": "sakura", "gloss_en": "cherry blossom"})


def test_cli_placeholder_writes_image_columns():
    d = Path(tempfile.mkdtemp())
    spine, out = d / "spine.csv", d / "images.csv"
    _write_spine(spine)
    r = subprocess.run([sys.executable, str(SCRIPT), "fetch", "--spine", str(spine),
                        "--out", str(out), "--placeholder"],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    rows = list(_csv.DictReader(out.open(encoding="utf-8")))
    assert rows[0]["image_id"] == "kigo-03-25"
    assert list(rows[0].keys()) == list(fi.IMAGE_COLUMNS)


def test_cli_select_end_to_end():
    d = Path(tempfile.mkdtemp())
    imgs = d / "downloads"; imgs.mkdir()
    # two candidate files + a candidates.csv marking c2
    for n in (1, 2):
        fi.save_jpeg(Image.new("RGB", (1080, 2340), (n, n, n)),
                     imgs / f"kigo-03-25__c{n}.jpg", 82)
    cand = d / "candidates.csv"
    with cand.open("w", newline="", encoding="utf-8") as f:
        w = _csv.DictWriter(f, fieldnames=fi.CANDIDATE_COLUMNS)
        w.writeheader()
        w.writerow(_cand_row("2026-03-25", 1))
        w.writerow(_cand_row("2026-03-25", 2, chosen="x"))
    out = d / "images.csv"
    r = subprocess.run([sys.executable, str(SCRIPT), "select",
                        "--candidates-in", str(cand), "--out", str(out),
                        "--out-images", str(imgs)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert (imgs / "kigo-03-25.jpg").exists()  # canonical copy of the chosen c2
    rows = list(_csv.DictReader(out.open(encoding="utf-8")))
    assert rows[0]["attribution_credit_en"] == "Photo: Aki / Pexels"


def test_cli_select_rejects_ambiguous_marking():
    d = Path(tempfile.mkdtemp()); imgs = d / "downloads"; imgs.mkdir()
    cand = d / "candidates.csv"
    with cand.open("w", newline="", encoding="utf-8") as f:
        w = _csv.DictWriter(f, fieldnames=fi.CANDIDATE_COLUMNS); w.writeheader()
        w.writerow(_cand_row("2026-03-25", 1))  # zero chosen
    r = subprocess.run([sys.executable, str(SCRIPT), "select",
                        "--candidates-in", str(cand), "--out", str(d / "o.csv"),
                        "--out-images", str(imgs)], capture_output=True, text=True)
    assert r.returncode != 0
    assert "2026-03-25" in r.stderr
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — the subprocess returns non-zero because `fetch`/`select` subcommands don't exist yet (argparse error).

- [ ] **Step 3: Write minimal implementation**

Replace the existing `main` in `fetch_images.py` with subparser-based dispatch and orchestration. Keep `load_dotenv`, `_read_spine`, `_placeholder_row`, and the existing `IMAGE_COLUMNS`/`PROVIDERS`.

```python
import functools


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
    # adapt partial(term, lang, ...) to the (term, lang) signature collect expects
    search_fns = {p: (lambda f: (lambda term, lang: f(term, lang)))(fn)
                  for p, fn in search_fns.items()}

    out_rows, missing = [], []
    for row in rows:
        ladder = build_ladder(row, primary=args.primary, fallback=fallback,
                              use_japanese=not args.no_japanese)
        cands = collect_candidates(ladder, search_fns, args.min_width,
                                   args.min_height, args.candidates)
        if not cands:
            missing.append((row["date"], row.get("gloss_en") or row["reading_en"]))
            continue
        for i, cand in enumerate(cands, start=1):
            img = process_image(_download_image(cand["download_url"]),
                                aspect_w, aspect_h, args.max_edge)
            fname = f"{image_id_for(row['date'])}__c{i}.jpg"
            save_jpeg(img, args.out_images / fname, args.jpeg_quality)
            out_rows.append(candidate_row(row, cand, i, fname, img.width, img.height))
        print(f"  {row['date']} {row['kanji']}: {len(cands)} candidate(s)")

    _write_csv(args.candidates_out, CANDIDATE_COLUMNS, out_rows)
    print(f"wrote {len(out_rows)} candidate rows to {args.candidates_out}")
    if missing:
        print(f"  NOTE: {len(missing)} row(s) had no candidate — refine and rerun:",
              file=sys.stderr)
        for date, q in missing[:10]:
            print(f"    {date}: no result for {q!r}", file=sys.stderr)
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
```

Also update the module docstring's usage block to the new subcommands (see Task 9 for the wording; the docstring change can ride in this commit).

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS for the whole file; final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: fetch/select subcommands, candidate orchestration, CLI"
```

---

### Task 9: Docs — README + module docstring for the two-phase flow and Pillow

**Files:**
- Modify: `scripts/content/fill/README.md`
- Modify: `scripts/content/fill/fetch_images.py` (module docstring, if not already done in Task 8)
- Test: `scripts/content/fill/test_fetch_images.py` (docs assertions)

**Interfaces:** none (documentation).

- [ ] **Step 1: Write the failing test**

Add to `test_fetch_images.py`:

```python
README = FILL_DIR / "README.md"


def test_readme_documents_two_phase_and_pillow():
    text = README.read_text(encoding="utf-8")
    assert "fetch_images.py fetch" in text
    assert "fetch_images.py select" in text
    assert "candidates.csv" in text
    assert "Pillow" in text
    assert "chosen" in text  # the review column
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL on `test_readme_documents_two_phase_and_pillow` (`assert "fetch_images.py fetch" in text`).

- [ ] **Step 3: Write minimal implementation**

Update the **"Images (stage 4)"** section of `scripts/content/fill/README.md` to describe the two-phase flow. Replace that section's body with:

````markdown
Stage 4 is two-phase, human-in-the-loop (like `describe.py`'s emit/ingest).
It needs **Pillow** (the workflow's only non-stdlib dependency, used just here):

```bash
python3 -m pip install Pillow
```

Providers: **pexels** (primary) and **pixabay** (fallback), both free and
commercial-use; keys in the gitignored `scripts/content/fill/.env`
(`PEXELS_API_KEY` / `PIXABAY_API_KEY`). Each day is searched **Japanese-first**
(the kanji, then the English `gloss_en`, then romaji) across both providers,
keeping the top **3** distinct results that clear a min-resolution floor. Each
candidate is smart-cropped to the phone screen ratio (9:19.5), downscaled, and
JPEG-encoded — so you review the *actual* image that would ship.

```bash
# keyless placeholders, to build + gate the CSV before you have a key:
python3 scripts/content/fill/fetch_images.py fetch \
    --spine scripts/content/fill/spine-2026.csv \
    --out scripts/content/fill/images.csv --placeholder

# real: acquire + process 3 candidates per day
python3 scripts/content/fill/fetch_images.py fetch \
    --spine scripts/content/fill/spine-2026.csv \
    --candidates-out scripts/content/fill/candidates.csv \
    --out-images scripts/content/fill/downloads
```

Then **review**: open `candidates.csv`, look at the matching
`downloads/<image_id>__c1..c3.jpg`, and put any mark (e.g. `x`) in the `chosen`
column of the winner — exactly one per date. Resolve the choice:

```bash
python3 scripts/content/fill/fetch_images.py select \
    --candidates-in scripts/content/fill/candidates.csv \
    --out scripts/content/fill/images.csv \
    --out-images scripts/content/fill/downloads
```

`select` validates one `chosen` per date, copies each winner to the canonical
`<image_id>.jpg`, and writes the 8-column `images.csv` `build_csv.py` expects.
Days with no candidate are reported on stderr — refine the query and rerun.
Tuning flags: `--candidates`, `--per-page`, `--min-width/--min-height`,
`--aspect`, `--max-edge`, `--jpeg-quality`, `--no-japanese`, `--no-fallback`.
````

Also update the pipeline diagram line for stage 4 from `Pexels API (or --placeholder)` to `Pexels+Pixabay, Japanese-first (or --placeholder)`, and the "What you must supply" Pillow note. In the module docstring of `fetch_images.py`, replace the old single-phase usage examples with the `fetch` / `select` subcommand examples above.

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS for the whole file; final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/README.md scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: document two-phase fetch/select flow + Pillow dependency"
```

---

## Final verification

- [ ] Run the full test file: `python3 scripts/content/fill/test_fetch_images.py` → ends with `ALL PASS`.
- [ ] Smoke-test the offline path end to end:
  ```bash
  python3 scripts/content/fill/fetch_images.py fetch \
      --spine scripts/content/fill/spine-2026.csv \
      --out /tmp/kigo-images.csv --placeholder && head -2 /tmp/kigo-images.csv
  ```
  Expected: 366 lines (header + 365), columns == `IMAGE_COLUMNS`.
- [ ] Confirm the existing content pipeline still gates: `python3 scripts/content/test_pipeline.py` → `ALL PASS` (unchanged; `images.csv` contract preserved).

## Notes for the implementer

- The `search_fns` double-lambda in `cmd_fetch` adapts each `functools.partial` (bound to key/per_page/sleep) to the `(term, lang)` signature `collect_candidates` calls; the extra wrapper captures `fn` per-iteration to avoid the late-binding closure bug. Keep it.
- `_download_image` uses the existing `_get` (browser User-Agent) — required; Pixabay's CDN 403s the default urllib UA.
- `src_w/src_h` in `candidates.csv` are the **processed** (post-crop) dimensions read off the PIL image — the true size of the asset the reviewer sees, not the provider's metadata.
- Do not re-rank candidates; provider relevance order is intentional (spec §"rejected options").
