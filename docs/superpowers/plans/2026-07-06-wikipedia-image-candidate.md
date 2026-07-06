# Wikipedia Image Candidate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Wikipedia/Wikimedia lead image as a 4th per-kigo candidate that is shippable when its license permits, and always shown as an accuracy reference for the stock picks.

**Architecture:** A keyless, per-row, single-lead-image source handled *outside* the stock round-robin ladder: `cmd_fetch` appends one Wikipedia candidate after the 3 stock candidates. Pure helpers (license gate, HTML strip, JSON parsers, candidate assembler) are unit-tested; the two-call HTTP lookup wrapper is correct-by-inspection (network, off any gated path). `candidates.csv` grows two columns (`usable`, `note`); `select` refuses to ship a reference-only pick.

**Tech Stack:** Python 3 stdlib (`urllib`, `json`, `re`, `html`) + Pillow (already used). Tests: stdlib `assert` in `test_*()` functions run directly (no pytest), matching the existing `scripts/content/fill/test_fetch_images.py`.

## Global Constraints

- **Test convention:** stdlib only, no pytest/unittest classes; plain `test_*()` with bare `assert`; the `__main__` discovery runner (`fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]`) stays LAST in the file. Run with `python3 scripts/content/fill/test_fetch_images.py`; success is the final line `ALL PASS`.
- **Test output must be pristine.** Also prove with `python3 -W error::DeprecationWarning scripts/content/fill/test_fetch_images.py`.
- **No network in tests.** The lookup/download HTTP wrappers are NOT unit-tested (correct by inspection); JSON parsers and pure logic are tested with in-memory sample data.
- **Shippable license allowlist:** not `NonFree`, and license code starts with `cc0` / `pd` / `cc-by` (covers `cc-by` and `cc-by-sa`), or short name contains "public domain". Everything else → `usable="no"` (reference-only).
- **Reference-only images are never selectable and never shipped** — `select_chosen` rejects a chosen row with `usable="no"`.
- **Wikimedia User-Agent:** API calls send `WIKI_UA = "kigo-content-pipeline/1.0 (+https://github.com/aonsager/kigo)"`, not the browser `USER_AGENT`.
- **`images.csv` schema is frozen** at the 8 `IMAGE_COLUMNS`; `CANDIDATE_COLUMNS` grows from 16 to 18 (`+ "usable", "note"`).
- **Wikipedia provider name is the literal string `"wikipedia"`** and is NOT in the `PROVIDERS` dict (it needs no key and is not a ranked search).
- Preserve existing behavior: round-robin stock `collect_candidates`, per-row `try/except` resilience, `.env` key resolution, `_flat_data` (no deprecated `getdata`), and the `_download_image`/`process_image`/`save_jpeg` pipeline.

---

### Task 1: Pure helpers — HTML strip + license gate

**Files:**
- Modify: `scripts/content/fill/fetch_images.py` (add `import html`, `import re` to the imports; add two functions)
- Test: `scripts/content/fill/test_fetch_images.py`

**Interfaces:**
- Produces:
  - `_strip_html(s: str | None) -> str` — remove tags, unescape entities, strip.
  - `_wiki_license_shippable(license_code, license_short, nonfree) -> bool` — `nonfree` may be a bool or an extmetadata string (`"true"`).

- [ ] **Step 1: Write the failing test** (append above the `__main__` runner)

```python
def test_strip_html():
    assert fi._strip_html('<bdi><a href="x">KENPEI</a></bdi>') == "KENPEI"
    assert fi._strip_html("Tom &amp; Jerry") == "Tom & Jerry"
    assert fi._strip_html("") == "" and fi._strip_html(None) == ""


def test_wiki_license_shippable():
    for code, short, nf in [("pd", "Public domain", None), ("cc0", "CC0", None),
                            ("cc-by-4.0", "CC BY 4.0", None),
                            ("cc-by-sa-3.0", "CC BY-SA 3.0", None),
                            ("", "Public domain", None)]:
        assert fi._wiki_license_shippable(code, short, nf) is True, (code, short)
    for code, short, nf in [("gfdl", "GFDL", None), ("", "Fair use", None),
                            ("", "", None),
                            ("cc-by-sa-3.0", "CC BY-SA 3.0", True),   # non-free wins
                            ("cc-by-sa-3.0", "CC BY-SA 3.0", "true")]:
        assert fi._wiki_license_shippable(code, short, nf) is False, (code, short, nf)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `AttributeError: module 'fetch_images' has no attribute '_strip_html'`.

- [ ] **Step 3: Write minimal implementation**

Add `import html` and `import re` near the top imports. Then add:

```python
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
    if code.startswith(("cc0", "pd", "cc-by")):  # cc-by covers cc-by-sa
        return True
    return "public domain" in (license_short or "").strip().lower()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS; final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: HTML-strip + Wikimedia license-shippable helpers"
```

---

### Task 2: Wikimedia JSON parsers

**Files:**
- Modify: `scripts/content/fill/fetch_images.py`
- Test: `scripts/content/fill/test_fetch_images.py`

**Interfaces:**
- Produces:
  - `_parse_pageimages(data: dict) -> dict | None` — `{"title", "image_url", "filename"}` or `None` (missing page / no original image).
  - `_parse_imageinfo(data: dict) -> dict` — `{"width","height","license_short","license_code","nonfree","artist","license_url","description_url"}` (missing → `""`/`0`/`None`).

- [ ] **Step 1: Write the failing test**

```python
_PAGEIMAGES_SAMPLE = {"query": {"pages": [{
    "title": "オミナエシ", "pageimage": "Patrinia_scabiosifolia2.jpg",
    "original": {"source": "https://upload.wikimedia.org/x.jpg",
                 "width": 1712, "height": 2304}}]}}

_PAGEIMAGES_MISSING = {"query": {"pages": [{"title": "藁塚", "missing": True}]}}

_IMAGEINFO_SAMPLE = {"query": {"pages": [{"title": "File:Patrinia_scabiosifolia2.jpg",
    "imageinfo": [{
        "url": "https://upload.wikimedia.org/x.jpg", "width": 1712, "height": 2304,
        "descriptionurl": "https://commons.wikimedia.org/wiki/File:Patrinia_scabiosifolia2.jpg",
        "extmetadata": {
            "LicenseShortName": {"value": "CC BY-SA 3.0"},
            "License": {"value": "cc-by-sa-3.0"},
            "Artist": {"value": "KENPEI"},
            "LicenseUrl": {"value": "http://creativecommons.org/licenses/by-sa/3.0/"}}}]}]}}


def test_parse_pageimages():
    got = fi._parse_pageimages(_PAGEIMAGES_SAMPLE)
    assert got == {"title": "オミナエシ", "image_url": "https://upload.wikimedia.org/x.jpg",
                   "filename": "Patrinia_scabiosifolia2.jpg"}


def test_parse_pageimages_missing_returns_none():
    assert fi._parse_pageimages(_PAGEIMAGES_MISSING) is None
    assert fi._parse_pageimages({"query": {"pages": []}}) is None


def test_parse_imageinfo():
    info = fi._parse_imageinfo(_IMAGEINFO_SAMPLE)
    assert info["width"] == 1712 and info["height"] == 2304
    assert info["license_short"] == "CC BY-SA 3.0" and info["license_code"] == "cc-by-sa-3.0"
    assert info["artist"] == "KENPEI" and info["nonfree"] is None
    assert info["license_url"] == "http://creativecommons.org/licenses/by-sa/3.0/"
    assert info["description_url"].endswith("File:Patrinia_scabiosifolia2.jpg")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `AttributeError: module 'fetch_images' has no attribute '_parse_pageimages'`.

- [ ] **Step 3: Write minimal implementation**

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS; final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: Wikimedia pageimages + imageinfo JSON parsers"
```

---

### Task 3: Wikipedia candidate assembler

**Files:**
- Modify: `scripts/content/fill/fetch_images.py`
- Test: `scripts/content/fill/test_fetch_images.py`

**Interfaces:**
- Consumes: `_strip_html`, `_wiki_license_shippable` (Task 1), `passes_floor` (existing).
- Produces:
  - `_wiki_candidate(pageimg: dict, lang: str, info: dict, min_width: int, min_height: int) -> dict` — a normalized candidate with keys: `provider` (`"wikipedia"`), `photo_id`, `photographer`, `download_url`, `source_url`, `width`, `height`, `search_term`, `search_lang`, `license_ja`, `license_en`, `license_url`, `usable` (`"yes"`/`"no"`), `note`. `pageimg` is a `_parse_pageimages` result; `info` a `_parse_imageinfo` result.

- [ ] **Step 1: Write the failing test**

```python
def _pageimg(title="オミナエシ"):
    return {"title": title, "image_url": "https://img/x.jpg", "filename": "x.jpg"}


def _info(w=1712, h=2304, code="cc-by-sa-3.0", short="CC BY-SA 3.0", nonfree=None,
          artist="KENPEI", url="http://creativecommons.org/licenses/by-sa/3.0/",
          desc="https://commons.wikimedia.org/wiki/File:x"):
    return {"width": w, "height": h, "license_short": short, "license_code": code,
            "nonfree": nonfree, "artist": artist, "license_url": url,
            "description_url": desc}


def test_wiki_candidate_shippable():
    c = fi._wiki_candidate(_pageimg(), "ja", _info(), 800, 1200)
    assert c["provider"] == "wikipedia" and c["usable"] == "yes"
    assert c["photo_id"] == "x.jpg" and c["photographer"] == "KENPEI"
    assert c["download_url"] == "https://img/x.jpg"
    assert c["search_term"] == "オミナエシ" and c["search_lang"] == "ja"
    assert c["license_en"] == "CC BY-SA 3.0" and c["license_ja"] == "CC BY-SA 3.0"
    assert "article: オミナエシ" in c["note"] and "by-sa" in c["note"].lower()


def test_wiki_candidate_nonfree_is_reference_only():
    c = fi._wiki_candidate(_pageimg(), "ja", _info(nonfree="true"), 800, 1200)
    assert c["usable"] == "no" and c["note"].startswith("reference-only: non-free")


def test_wiki_candidate_below_floor_is_reference_only():
    c = fi._wiki_candidate(_pageimg(), "ja", _info(w=400, h=600), 800, 1200)
    assert c["usable"] == "no" and "below min resolution" in c["note"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `AttributeError: module 'fetch_images' has no attribute '_wiki_candidate'`.

- [ ] **Step 3: Write minimal implementation**

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS; final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: Wikipedia candidate assembler with usable/note"
```

---

### Task 4: candidates.csv schema + row builders + select guard

**Files:**
- Modify: `scripts/content/fill/fetch_images.py` (`CANDIDATE_COLUMNS`, `candidate_row`, `image_row_from_candidate`, `select_chosen`)
- Test: `scripts/content/fill/test_fetch_images.py` (update `_cand_row` helper; add tests)

**Interfaces:**
- Consumes: nothing new.
- Produces (changed contracts):
  - `CANDIDATE_COLUMNS` gains `"usable"`, `"note"` (now 18 columns).
  - `candidate_row(...)` takes license from `PROVIDERS[provider]` for stock providers, else from the candidate's own `license_ja`/`license_en`; carries `usable` (default `"yes"`) and `note` (default `""`).
  - `image_row_from_candidate(cand_row)` — Wikipedia credit is `画像: {author} / Wikimedia Commons` / `Image: {author} / Wikimedia Commons`.
  - `select_chosen(cand_rows)` — additionally rejects a chosen row whose `usable == "no"`.

- [ ] **Step 1: Write the failing test**

First, update the existing `_cand_row` helper (it must produce all 18 columns) — change its `return` to include the two new keys, and add a `usable` parameter:

```python
def _cand_row(date, idx, chosen="", provider="pexels", photographer="Aki", usable="yes"):
    return {"date": date, "image_id": fi.image_id_for(date), "candidate": str(idx),
            "chosen": chosen, "provider": provider, "search_term": "桜",
            "search_lang": "ja-JP", "photographer": photographer,
            "license_ja": "Pexels ライセンス", "license_en": "Pexels License",
            "title_ja": "桜", "title_en": "cherry blossom",
            "source_url": "s", "src_w": "1080", "src_h": "2340",
            "out_file": f"kigo-03-25__c{idx}.jpg", "usable": usable, "note": ""}
```

Then append these new tests:

```python
def test_candidate_row_wikipedia_uses_dynamic_license():
    row = {"date": "2026-04-15", "kanji": "女郎花", "gloss_en": "", "reading_en": "ominaeshi"}
    cand = {"provider": "wikipedia", "search_term": "オミナエシ", "search_lang": "ja",
            "photographer": "KENPEI", "source_url": "https://commons/File:x",
            "license_ja": "CC BY-SA 3.0", "license_en": "CC BY-SA 3.0",
            "usable": "yes", "note": "article: オミナエシ"}
    out = fi.candidate_row(row, cand, 4, "kigo-04-15__c4.jpg", 1080, 2340)
    assert set(out) == set(fi.CANDIDATE_COLUMNS)
    assert out["provider"] == "wikipedia" and out["license_en"] == "CC BY-SA 3.0"
    assert out["usable"] == "yes" and out["note"] == "article: オミナエシ"
    assert out["title_en"] == "ominaeshi"  # gloss_en empty -> reading_en


def test_image_row_from_wikipedia_credit():
    cr = _cand_row("2026-04-15", 4, chosen="x", provider="wikipedia", photographer="KENPEI")
    cr["license_ja"] = cr["license_en"] = "CC BY-SA 3.0"
    out = fi.image_row_from_candidate(cr)
    assert out["attribution_credit_en"] == "Image: KENPEI / Wikimedia Commons"
    assert out["attribution_credit_ja"] == "画像: KENPEI / Wikimedia Commons"
    assert out["attribution_license_en"] == "CC BY-SA 3.0"


def test_select_chosen_rejects_reference_only():
    rows = [_cand_row("2026-03-25", 1, chosen="x", usable="no"),
            _cand_row("2026-03-25", 2)]
    try:
        fi.select_chosen(rows)
    except ValueError as e:
        assert "reference-only" in str(e) and "2026-03-25" in str(e)
    else:
        raise AssertionError("expected ValueError")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `test_candidate_row_wikipedia_uses_dynamic_license` raises `KeyError: 'wikipedia'` (current `candidate_row` does `PROVIDERS[cand["provider"]]`), and/or the set-equality assertion fails because `usable`/`note` aren't in `CANDIDATE_COLUMNS` yet.

- [ ] **Step 3: Write minimal implementation**

Extend `CANDIDATE_COLUMNS`:

```python
CANDIDATE_COLUMNS = (
    "date", "image_id", "candidate", "chosen",
    "provider", "search_term", "search_lang", "photographer",
    "license_ja", "license_en", "title_ja", "title_en",
    "source_url", "src_w", "src_h", "out_file", "usable", "note",
)
```

Replace `candidate_row` with:

```python
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
```

Replace `image_row_from_candidate` with:

```python
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
```

Replace `select_chosen` with:

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: PASS for the whole file (existing `test_candidate_row_shape`, `test_image_row_from_candidate_builds_attribution`, `test_select_chosen_*`, `test_cli_select_end_to_end` still pass — `_cand_row` now supplies all 18 columns and `usable="yes"`); final line `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: candidates.csv usable/note columns, dynamic license, select guard"
```

---

### Task 5: Wikipedia lookup + fetch wiring + docs

**Files:**
- Modify: `scripts/content/fill/fetch_images.py` (add `WIKI_UA`, `_wiki_api`, `_wikipedia_lookup`; wire into `cmd_fetch`; add `--no-wikipedia`; update module docstring)
- Modify: `scripts/content/fill/README.md`
- Test: `scripts/content/fill/test_fetch_images.py`

**Interfaces:**
- Consumes: `_parse_pageimages`, `_parse_imageinfo`, `_wiki_candidate` (Tasks 2–3), `_get`, `_download_image`, `process_image`, `save_jpeg`, `candidate_row`, `image_id_for` (existing).
- Produces: `_wikipedia_lookup(kanji, gloss_en, min_width, min_height) -> dict | None` (network; not unit-tested). `cmd_fetch` appends one Wikipedia candidate per row unless `--no-wikipedia`.

- [ ] **Step 1: Write the failing test**

```python
def test_cli_fetch_has_no_wikipedia_flag():
    r = subprocess.run([sys.executable, str(SCRIPT), "fetch", "-h"],
                       capture_output=True, text=True)
    assert r.returncode == 0
    assert "--no-wikipedia" in r.stdout


def test_readme_documents_wikipedia_reference():
    text = README.read_text(encoding="utf-8")
    assert "Wikipedia" in text
    assert "reference" in text.lower()
    assert "usable" in text
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `test_cli_fetch_has_no_wikipedia_flag` fails (`--no-wikipedia` not in help), and `test_readme_documents_wikipedia_reference` fails (README not updated).

- [ ] **Step 3: Write minimal implementation**

Add near the existing `USER_AGENT` constant:

```python
# Wikimedia asks API clients to send a descriptive User-Agent with a URL/contact.
WIKI_UA = "kigo-content-pipeline/1.0 (+https://github.com/aonsager/kigo)"
```

Add the lookup helpers (near the other search adapters):

```python
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
```

Rewrite the per-row loop body in `cmd_fetch` (the `for row in rows:` block) so it also appends the Wikipedia candidate and treats an empty row correctly. Replace the current try-body with:

```python
        try:
            ladder = build_ladder(row, primary=args.primary, fallback=fallback,
                                  use_japanese=not args.no_japanese)
            cands = collect_candidates(ladder, search_fns, args.min_width,
                                       args.min_height, args.candidates)
            row_out = []
            for i, cand in enumerate(cands, start=1):
                img = process_image(_download_image(cand["download_url"]),
                                    aspect_w, aspect_h, args.max_edge)
                fname = f"{image_id_for(row['date'])}__c{i}.jpg"
                save_jpeg(img, args.out_images / fname, args.jpeg_quality)
                row_out.append(candidate_row(row, cand, i, fname, img.width, img.height))
            if not args.no_wikipedia:
                wiki = _wikipedia_lookup(row["kanji"],
                                         row.get("gloss_en") or row["reading_en"],
                                         args.min_width, args.min_height)
                if wiki:
                    idx = len(row_out) + 1
                    img = process_image(_download_image(wiki["download_url"]),
                                        aspect_w, aspect_h, args.max_edge)
                    fname = f"{image_id_for(row['date'])}__c{idx}.jpg"
                    save_jpeg(img, args.out_images / fname, args.jpeg_quality)
                    row_out.append(candidate_row(row, wiki, idx, fname,
                                                 img.width, img.height))
            if not row_out:
                missing.append((row["date"], row.get("gloss_en") or row["reading_en"]))
                continue
            out_rows.extend(row_out)
            print(f"  {row['date']} {row['kanji']}: {len(row_out)} candidate(s)")
        except Exception as e:  # one bad row must not discard the whole run
            errors.append((row["date"], repr(e)))
            print(f"  {row['date']} {row['kanji']}: ERROR {e}", file=sys.stderr)
            continue
```

Add the CLI flag alongside the other `fetch` args (after `--no-japanese`):

```python
    pf.add_argument("--no-wikipedia", action="store_true")
```

Update the module docstring's `fetch` description to mention the 4th Wikipedia candidate (add a sentence such as: "Also append the Japanese Wikipedia lead image (ja by kanji, then en by gloss_en) as a licensed 4th candidate and accuracy reference — shippable only when its license is PD/CC0/CC-BY/CC-BY-SA, else marked reference-only; disable with --no-wikipedia.").

Update the README "Images (stage 4)" section: add a short paragraph after the round-robin description, e.g.:

````markdown
Alongside the stock candidates, each day also gets the **Japanese Wikipedia lead
image** (looked up by kanji, then by the English `gloss_en` on English
Wikipedia) as a licensed **4th candidate and accuracy reference**. Its real
license is read from Wikimedia; it is marked **`usable`** in `candidates.csv`
only when that license permits shipping (public-domain / CC0 / CC-BY / CC-BY-SA)
and it clears the resolution floor — otherwise it is kept **reference-only** so
you can still check whether the stock picks show the right subject, but `select`
will refuse to ship it. Disable with `--no-wikipedia`.
````

- [ ] **Step 4: Run test to verify it passes**

Run both:
`python3 scripts/content/fill/test_fetch_images.py` → `ALL PASS`
`python3 -W error::DeprecationWarning scripts/content/fill/test_fetch_images.py` → `ALL PASS`, pristine

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/README.md scripts/content/fill/test_fetch_images.py
git commit -m "fill/images: append Wikipedia lead image as 4th candidate + accuracy reference"
```

---

## Final verification

- [ ] Full suite: `python3 -W error::DeprecationWarning scripts/content/fill/test_fetch_images.py` → `ALL PASS`, pristine.
- [ ] Placeholder path unaffected:
  ```bash
  python3 scripts/content/fill/fetch_images.py fetch \
      --spine scripts/content/fill/spine-2026.csv --out "$TMPDIR/img.csv" --placeholder
  ```
  Expected: "wrote 365 placeholder image rows"; header is the 8 `IMAGE_COLUMNS`.
- [ ] Help lists the flag: `python3 scripts/content/fill/fetch_images.py fetch -h | grep -- --no-wikipedia`.
- [ ] (Optional, network, human-run) Live smoke on the sample spine, then confirm a 4th `wikipedia` row appears where an article exists and `usable`/`note` are populated:
  ```bash
  python3 scripts/content/fill/fetch_images.py fetch \
      --spine scripts/content/fill/spine-sample.csv \
      --candidates-out "$TMPDIR/cand.csv" --out-images "$TMPDIR/dl"
  ```

## Notes for the implementer

- The Wikipedia candidate is appended **inside** the existing per-row `try/except`, so a lookup or download failure for one row logs to `errors` and is skipped — never aborting the run (matches the stock path).
- `_wikipedia_lookup` / `_wiki_api` are the only network additions and are NOT unit-tested (correct by inspection), exactly like `_pexels_search` / `_pixabay_search`.
- Wikipedia's `photo_id` is the file name; it dedupes within a row only (it is one extra candidate, so collisions with stock ids don't matter — stock dedup is keyed by `(provider, photo_id)` inside `collect_candidates`, which the Wikipedia candidate never enters).
- Do not add a `license_url` column to `candidates.csv`; the URL lives inside `note` (per the spec's non-goals — the shipped manifest carries only the license short name).
