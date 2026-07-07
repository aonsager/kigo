# Wikipedia/Wikimedia as a 4th image candidate + accuracy reference

**Date:** 2026-07-06
**Status:** Approved (brainstorming) — pending implementation plan
**Touches:** `scripts/content/fill/fetch_images.py`, `scripts/content/fill/README.md`
**Relates to:** ADR 0022 (remote image delivery; image curation is a human step),
ADR 0024 (English `gloss_en` search helper), and the smart-image-selection design
(`2026-07-06-smart-image-selection-design.md`) this extends.

## Problem

Stage 4 now offers 3 stock candidates per kigo (Pexels/Pixabay, drawn
round-robin across search rungs). Two gaps remain:

1. **No ground truth.** Live testing showed Pexels never returns empty — it
   substitutes popular photos for an unmatched Japanese query — so a stock
   candidate can be a confident-looking but *wrong* subject (e.g. "yellow
   valerian" stock photos for 女郎花, which is actually オミナエシ / *Patrinia
   scabiosifolia*). The human curator has no reference to catch this.
2. **A missed free, on-point source.** The Japanese Wikipedia article for a
   kigo often carries a correctly-identified, freely-licensed lead image
   (verified 2026-07-06: 女郎花 → オミナエシ → a CC BY-SA 3.0 botanical photo).

Adding the Wikipedia lead image serves both: a **4th candidate** when its
license permits shipping, and an **accuracy reference** the reviewer compares
the stock picks against even when it can't be shipped.

## Research findings (2026-07-06, live)

- **License is readable per-image.** Commons `imageinfo` → `extmetadata` gives
  `LicenseShortName` (e.g. "CC BY-SA 3.0"), a `License` code (e.g. `pd`,
  `cc-by-sa-3.0`), a `NonFree` flag, `Artist` (HTML), and `LicenseUrl`.
- **Not every kigo has an article.** 藁塚, 初烏 return `missing` — Wikipedia is
  a *bonus* 4th, never guaranteed.
- **Redirects matter.** 女郎花 redirects to オミナエシ (`redirects=1` follows it).
- **The lead image is not always a subject photo.** 花見's lead image is a
  Public-Domain ukiyo-e, not cherry blossoms — culturally representative, still
  useful as a reference, and PD so shippable.

## Decisions (approved)

1. **Role:** always fetch the lead image (when the article exists), label it
   `provider="wikipedia"`, record its real license, and mark it **shippable or
   reference-only**. The reviewer always sees it; `select` only lets them
   *choose* it when shippable.
2. **Shippable licenses:** PD/CC0 + CC-BY + CC-BY-SA (with author credit +
   license line recorded; share-alike applies to the cropped derivative, which
   the attribution captures). Non-free / GFDL-only / unknown → reference-only.
3. **Lookup fallback:** ja.wikipedia on the kanji (follow redirects); if
   missing, en.wikipedia on `gloss_en`.
4. **Crop treatment:** same 9:19.5 smart-crop → resize(never upscale) → JPEG as
   the stock candidates (like-for-like review). The min-resolution floor is
   **not** a rejection for Wikipedia — small images are still shown as
   reference — only a shippability signal.

## Design

Wikipedia is a **keyless, per-row, single-lead-image** source, handled
**outside** the stock round-robin ladder. Per row: collect up to `--candidates`
(3) stock candidates as today, then try to append **one** Wikipedia candidate →
up to 4 total, saved as the next `__cN.jpg`.

### 1. Lookup — `_wikipedia_lookup(kanji, gloss_en)` (network, not unit-tested)

- ja.wikipedia: `action=query&format=json&formatversion=2&redirects=1&
  prop=pageimages&piprop=original|name&titles=<kanji>`. If the page exists and
  has an `original` image, use it; capture the resolved `title` and `pageimage`
  filename.
- If missing/no image, retry the same call on en.wikipedia with `<gloss_en>`
  (skip if `gloss_en` is empty).
- Then `action=query&prop=imageinfo&iiprop=extmetadata|url|size&
  titles=File:<pageimage>` **on the same wiki** (MediaWiki resolves Commons
  files through the local wiki).
- Assemble via the pure normalizer (§3) and return a candidate dict, or `None`
  if no article/image on either wiki.
- User-Agent: `kigo-content-pipeline/1.0 (+https://github.com/aonsager/kigo)`
  (Wikimedia asks for a descriptive UA), passed via `_get`'s header override.
- `--no-wikipedia` skips the whole step.

### 2. Pure helpers (unit-tested)

- `_strip_html(s) -> str` — drop tags and unescape entities (`html.unescape`
  + a tag regex) so `Artist` like `<bdi><a …>KENPEI</a></bdi>` → `KENPEI`.
- `_wiki_license_shippable(license_code, license_short, nonfree) -> bool` —
  `False` if `nonfree` is truthy; else `True` iff the lowercased code starts
  with `cc0` / `pd` / `cc-by` (covers `cc-by` **and** `cc-by-sa`) **or** the
  short name contains "public domain". All else (`gfdl*`, "fair use", empty,
  unknown) → `False`.
- `_parse_pageimages(data) -> dict|None` — from the pageimages response return
  `{"title", "image_url", "filename"}` or `None` (missing page / no original).
- `_parse_imageinfo(data) -> dict` — return `{"width","height",
  "license_short","license_code","nonfree","artist","license_url",
  "description_url"}` from the imageinfo `extmetadata`/`url`/`size` (missing
  fields default to "" / 0 / None).

### 3. Candidate assembler — `_wiki_candidate(title, lang, info, min_width, min_height) -> dict` (pure, unit-tested)

Builds the normalized candidate the pipeline consumes:

```
{ "provider": "wikipedia",
  "photo_id": <filename>,               # dedupe key within the row
  "photographer": _strip_html(artist) or "Unknown",
  "download_url": <original image url>,
  "source_url": <description_url>,       # the File: page (license/verify)
  "width": <int>, "height": <int>,
  "search_term": <resolved article title>,
  "search_lang": <"ja" | "en">,
  "license_ja": <license_short>, "license_en": <license_short>,
  "license_url": <license_url>,
  "usable": "yes" | "no",
  "note": <"" if usable else reason>,   # + article title / license url context
}
```

`usable = "yes"` iff `_wiki_license_shippable(...)` **and**
`passes_floor(width, height, min_width, min_height)`. The `note` always carries
the human record — the resolved article title and `license_url` — and is
**prefixed** with the reason(s) when `usable="no"`: `"reference-only: non-free
license"` and/or `"reference-only: below min resolution"`. So a shippable
Wikipedia row still gets an informative `note` (article + license URL); a
reference-only one leads with why.

### 4. `candidates.csv` — two new columns (16 → 18)

Append to `CANDIDATE_COLUMNS`: **`usable`** (`yes`/`no`) and **`note`**.

- Stock candidates: `usable="yes"`, `note=""`, license from `PROVIDERS` (as
  today).
- Wikipedia candidates: `usable`/`note`/license/photographer from the assembler.

`candidate_row(row, cand, index, out_file, src_w, src_h)` generalizes: license
comes from `PROVIDERS[provider]` when the provider is a known stock provider,
else from the candidate's own `license_ja`/`license_en`; `usable` and `note`
read from the candidate (defaulting to `"yes"`/`""` for stock).

### 5. Attribution — `image_row_from_candidate(cr)`

- Stock (unchanged): `写真: {photographer} / {Provider}` /
  `Photo: {photographer} / {Provider}`.
- Wikipedia: `画像: {photographer} / Wikimedia Commons` /
  `Image: {photographer} / Wikimedia Commons` (画像/Image — the source may be a
  painting or diagram, not a photo). License = the recorded short name.

### 6. `select` — `select_chosen(cand_rows)`

In addition to the existing "exactly one `chosen` per date" rule, a chosen row
whose `usable == "no"` is a hard error (message names the date and reason) — a
reference-only image can never be shipped.

### 7. `fetch` orchestration (`cmd_fetch`)

After the stock loop appends each row's candidates, and unless `--no-wikipedia`,
call `_wikipedia_lookup(row["kanji"], row.get("gloss_en") or row["reading_en"])`
inside the existing per-row `try/except`. If it returns a candidate: download →
`process_image` (crop/resize) → `save_jpeg` as `__c<next>.jpg`, append its
`candidate_row`. A lookup failure or a per-row error is caught and skipped
exactly like the stock path (partial progress preserved).

## Testing

Offline unit tests (stdlib `assert`, no network — mirrors the existing suite):

- `_wiki_license_shippable`: `pd`, `cc0`, `cc-by-4.0`, `cc-by-sa-3.0` → True;
  `gfdl`, `fair use`, `""`, and `nonfree=True` (even with a free license) →
  False; short-name "Public domain" with empty code → True.
- `_strip_html`: the `<bdi><a>KENPEI</a></bdi>` case and an entity case.
- `_parse_pageimages` / `_parse_imageinfo`: sample JSON → expected dicts;
  missing-page response → `None`.
- `_wiki_candidate`: a shippable case (`usable="yes"`), a non-free case and a
  below-floor case (`usable="no"` with the right `note`).
- `candidate_row`: a Wikipedia candidate carries dynamic license + `usable` +
  `note`; a stock candidate still gets `PROVIDERS` license + `usable="yes"`.
- `image_row_from_candidate`: Wikipedia credit uses `画像 … / Wikimedia Commons`.
- `select_chosen`: rejects a chosen row with `usable="no"`.

The lookup + download HTTP wrappers stay off any gated/automated path (human-run
stage, ADR 0022), consistent with the Pexels/Pixabay adapters.

## Non-goals

- No fuzzy/full-text article search beyond kanji-then-gloss (YAGNI; the direct
  title lookup with redirects is the on-point path).
- No license URL in the shipped manifest (the manifest attribution carries the
  short name; the URL lives in `candidates.csv` `note` for the human record) —
  a manifest-schema change is out of scope here.
- Reference-only (non-free) images are downloaded to the gitignored
  `downloads/` for **local review only** — never selected, never re-hosted.
