# Smart image selection for the kigo-2026 fill workflow

**Date:** 2026-07-06
**Status:** Approved (brainstorming) — pending implementation plan
**Touches:** `scripts/content/fill/fetch_images.py`, `scripts/content/fill/README.md`
**Relates to:** ADR 0022 (remote image delivery; image curation is a human step),
ADR 0024 (English kigo translation / `gloss_en` search helper).

## Problem

Stage 4 of the fill workflow (`fetch_images.py`) currently queries a single
stock provider with an English term, takes the **top-1** result verbatim, and
downloads it as-is. Three weaknesses matter for imagery that ships as a
**full-bleed portrait background** (the Today screen renders it with
`.scaledToFill()` — a naive centre-crop — on a ~9:19.5 phone screen):

1. **No quality control.** The top hit can be tiny, or the wrong shape.
2. **No crop control.** Portrait sources are still much *wider* than the screen
   (2:3 ≈ 0.667 vs ~9:19.5 ≈ 0.462), so the device silently centre-crops the
   sides — often cutting the subject.
3. **English-only search misses Japan-specific kigo.** Terms like 七夕, 節分,
   鏡開き have thin or culturally-wrong English stock; the kanji is the right query.

## Goals

- Prefer Japanese search terms, fall back to English, across two free providers.
- Apply a lightweight quality gate (min resolution) and a **content-aware crop**
  to the target screen ratio, baked into the re-hosted asset.
- Give the human curator (ADR 0022) **3 fully-processed candidates** per day to
  choose from, and a simple, auditable way to record the choice.
- Keep the network stages off any gated/automated path (human-run, per ADR 0022).

## Non-goals / rejected options (with rationale)

- **Switching to a dedicated Japanese stock service.** Researched 2026-07-06:
  the free Japanese services are not automatable — **photoAC** caps free keyword
  search at 4/day with no usable public API; **PAKUTASO** never shipped a public
  API and needs a link-back; **Photock** has no API and ~8,900 images total.
  **PIXTA** is the one quality Japanese option with a real search+download API
  and native JP tagging, but it is **paid** (from ¥165/image pay-per-use trial,
  then a monthly B2B contract). Decision: stay on the free tier and search it in
  Japanese; PIXTA is documented here as a future paid adapter, not built now.
- **Pixel-level quality gates** (exposure/flatness). Considered and dropped
  (YAGNI): the min-resolution floor plus human review of 3 candidates is enough.
- **Re-ranking candidates** (e.g. by Pixabay engagement). Dropped; we trust the
  provider's own relevance order and let the human pick among the top 3.

## Dependency decision

The smart-crop and JPEG re-encode need real image decoding, which the Python
stdlib cannot do for JPEG. **Add Pillow** to the image stage. The README's
"stdlib only, no third-party packages" claim is narrowed to *"stdlib only except
the image stage, which needs Pillow"*, with a one-line install note
(`python3 -m pip install Pillow`). All other stages stay stdlib-only.

## Design

`fetch_images.py` becomes a **two-phase, human-in-the-loop** tool with
subcommands, mirroring `describe.py`'s `emit`/`ingest` split:

```
fetch  ──►  candidates.csv  +  downloads/<image_id>__c1..c3.jpg
                 │
                 ▼   human marks the winner in the `chosen` column
select ──►  images.csv (8-col contract)  +  downloads/<image_id>.jpg
                 │
                 ▼
build_csv.py  (unchanged)
```

### 1. `fetch` — candidate acquisition

**Attempt ladder.** Per spine row, build an ordered list of `(provider, term,
lang)` attempts and walk it, **accumulating up to `--candidates` (default 3)**
distinct candidates that clear the resolution floor. Keep walking rungs until
the quota is filled or the ladder is exhausted. Default ladder:

| # | Provider | Term (spine column) | Lang |
|---|----------|---------------------|------|
| 1 | primary (Pexels) | `kanji` (桜) | `locale=ja-JP` |
| 2 | primary (Pexels) | `gloss_en` (→ `reading_en` if empty) | en |
| 3 | fallback (Pixabay) | `kanji` | `lang=ja` |
| 4 | fallback (Pixabay) | `gloss_en` | en |
| 5 | primary (Pexels) | `reading_en` (romaji) | en — last resort |

- **Dedupe** across rungs by provider photo id / source URL so the 3 candidates
  are genuinely distinct.
- Each provider search fetches `--per-page` (default 10) candidates; ranking is
  the **provider's own relevance order** (no re-ranking).
- Flags: `--primary pexels`, `--fallback pixabay`, `--no-fallback` (drop
  fallback rungs), `--no-japanese` (drop the kanji rungs — for A/B testing the
  hypothesis), `--candidates 3`, `--per-page 10`.

**Quality gate — min-resolution floor only** (`--min-height 1200`,
`--min-width 800`), tested against the **downloadable** dimensions, not the
metadata original:
- **Pexels:** downloadable via `src.original` = full resolution, so the
  candidate's metadata `width/height` *are* the downloadable dims.
- **Pixabay:** the free-tier `largeImageURL` is capped at **~1280px on the long
  edge** (full-res `imageURL` needs elevated access). So compute effective dims
  by scaling the metadata `imageWidth/imageHeight` down so the long edge is
  `min(originalLongEdge, 1280)`, and test the floor against *that*.

**Processing (each accepted candidate).** Download the chosen size (Pexels
`original`; Pixabay `largeImageURL`), then:
1. **Smart-crop** to `--aspect` (default `9:19.5`) — see §3.
2. **Resize** so the long edge ≤ `--max-edge` (default `2340`), **never
   upscale** (a small Pixabay fallback stays at its native size).
3. **Re-encode** JPEG at `--jpeg-quality` (default `82`), stripping metadata.
4. Write to `<out-images>/<image_id>__cN.jpg` (N = 1..candidates).

**Output — `candidates.csv`**, one row per candidate, carrying everything the
reviewer sees and the resolver needs (so `select` reads only this file):

```
date, image_id, candidate, chosen,
provider, search_term, search_lang, photographer,
license_ja, license_en, title_ja, title_en,
source_url, src_w, src_h, out_file
```

- `chosen` is written **blank**; the reviewer fills it in.
- `title_ja` = `kanji`, `title_en` = `gloss_en || reading_en` (the attribution
  title fields, precomputed here).
- Rows that yield **zero** candidates are omitted from `candidates.csv` and
  listed on stderr (today's missing-rows report), so the reviewer can refine and
  rerun. `build_csv.py` already emits only dates present in all inputs, so a
  partial year stays valid.

**`--placeholder`** remains a mode of `fetch`: it writes `images.csv` **directly**
(gate-passing placeholder attribution, no network, no candidates, no `select`
step) — exactly as today.

### 2. `select` — resolve the human's choice

- Read `candidates.csv`. **Validate exactly one `chosen` row per date**; error
  (non-zero exit) listing any date with zero or multiple marks.
- For each chosen candidate: copy `out_file` → `<out-images>/<image_id>.jpg`
  (the canonical name the manifest's `imageBaseURL + "/" + image_id + ".jpg"`
  convention expects), and build the final `images.csv` row from the eight
  `IMAGE_COLUMNS`, sourcing attribution from the candidate's provenance:
  - `attribution_title_ja/en` ← `title_ja/en`
  - `attribution_credit_ja` ← `写真: {photographer} / {Provider}`
  - `attribution_credit_en` ← `Photo: {photographer} / {Provider}`
  - `attribution_license_ja/en` ← `license_ja/en`
- Write `images.csv` (unchanged 8-col contract). `build_csv.py` consumes it
  as before.

### 3. Smart-crop algorithm (gist ported to Pillow)

Faithful port of the reference gist (entropy edge-trim), with a performance fix.

- Sources are portrait-but-wider than 9:19.5, so the **column-trim** branch runs:
  the image needs columns removed. (The symmetric **row-trim** branch is retained
  for the rare source taller than the target.)
- Quantize the image to **16 colours** (`img.quantize(colors=16)`).
- Greedily remove the **edge column with fewer unique colours** (the visually
  flatter / less informative side), repeating until at the target ratio.
- **Optimization vs. the gist:** the crop window only ever slides inward and
  columns are never modified, so precompute each column's unique-colour count
  **once**, then run a two-pointer trim — O(W·H) instead of the gist's
  O(W²·H) per-iteration rescan. Same result, no per-iteration `get_pixels`.

### 4. CLI summary

```
fetch_images.py fetch  --spine SPINE --candidates-out candidates.csv
                       --out-images DIR
                       [--primary pexels] [--fallback pixabay]
                       [--no-fallback] [--no-japanese]
                       [--candidates 3] [--per-page 10]
                       [--min-height 1200] [--min-width 800]
                       [--aspect 9:19.5] [--max-edge 2340] [--jpeg-quality 82]
                       [--api-key ...] [--sleep 0.7]
fetch_images.py fetch  --spine SPINE --out images.csv --placeholder
fetch_images.py select --candidates-in candidates.csv --out images.csv
                       --out-images DIR
```

Key resolution (`.env` / env var / `--api-key`), `--sleep` throttle + 429
backoff, and the browser-like User-Agent are unchanged.

## Testing

Pure-function / offline unit tests (no network, no simulator — mirrors the
repo's injected-seam discipline):

- **Attempt-ladder construction & walk** — given stubbed provider responses,
  assert the rung order, dedupe, `--no-japanese` / `--no-fallback` behavior, and
  that it stops at `--candidates`.
- **Resolution floor** — including the **Pixabay 1280 long-edge cap math**
  (a 4000×6000 Pixabay hit is judged on its ~853×1280 downloadable size).
- **Smart-crop** — on a synthesized PIL image with a known busy/flat split,
  assert it trims the flat side and hits the target ratio; assert the row-trim
  branch on a tall input; assert **never-upscale** on a small input.
- **`select` validation** — errors on zero/multiple `chosen` per date; correct
  `images.csv` rows and canonical file copy on a valid marking.

Network search + download stay **off any gated path** (human-run stage, ADR
0022), consistent with how the RemoteManifestSource/KigoImageSource network
fetches are kept off the loop's gating path.

## Risks & mitigations

- **Japanese-tagged stock is sparse on free providers.** Mitigated by the ladder
  (English rungs still resolve generic kigo) and by the human choosing among 3;
  if free results prove culturally thin for the hard kigo, the documented PIXTA
  paid adapter is the next step.
- **Pixabay fallback images are low-res (≤1280).** Accepted: they only appear
  when Pexels has nothing; never-upscale keeps them honest, and the human can
  reject a too-small candidate.
- **Pexels rate limit (200/hr).** A full 365-row run self-paces via `--sleep`
  and 429 backoff; it is a one-time, human-run job, so wall-clock is acceptable.
