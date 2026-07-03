# Kigo Content Catalog Assembly — Design

**Date:** 2026-07-03
**Status:** Approved (brainstorm) — pending spec review → implementation plan

## Goal

Replace the instrumented dummy Daily Map with a **real, shippable catalog of 365
daily kigo for 2026**. Each entry carries: the word (kanji), the hiragana reading
(JP; blank/romaji for the EN side), a short description (EN + JP), and a
royalty-free image. The app already reads this content through the `ContentSource`
seam; this work produces the content and adds the image-delivery path.

## Decisions (load-bearing)

| Dimension | Decision |
|---|---|
| Text source | Authoritative **saijiki dataset** as the correctness spine (kanji, reading, season); descriptions layered on top |
| Image source | **Stock photo APIs** (Pexels first) |
| Image delivery | **Remote URLs + on-device cache** (new app work) |
| Catalog lifespan | **2026-specific**, current absolute `2026-MM-DD` keying (no read-path change; ADR 0016 stands) |
| Pipeline shape | **Blended A+B**: scripts fetch/draft/re-host/assemble, but read/write one reviewable CSV that is the human review surface; manifest is always regenerated from it |
| Kō / Sekki | **Left as-is** — this pass assembles the 365 daily kigo only |
| Widget images | **Widget stays on the gradient placeholder** (respects ADR 0019's app-group removal); real photos are an in-app enhancement only |
| Sequencing | **Content pipeline first**, then the app image-delivery code |

## What already exists (do not rebuild)

- `Manifest` / `DailyMapEntry` schema already has exactly the needed fields:
  `kanji`, `reading` (`LocalizedText` ja + optional en), `description`
  (`LocalizedText` ja + optional en), `imageId`, `attribution` (title/credit/license).
- `ContentSource` seam + `BundledContentSource` reading `Resources/manifest.json`;
  `RemoteManifestSource` seam for future network refresh; monotonic `version`.
- `KigoPlaceholderView` deterministic gradient from `imageId` — becomes the
  loading/offline state rather than the permanent visual.
- `scripts/generate_daily_map.py`, `scripts/localize_manifest.py`,
  `ManifestValidationTests` — folded into / extended by the pipeline.

## Architecture & data flow

Single source of truth: **`content/kigo-2026.csv`** (one row per 2026 date),
checked into the repo as the audit trail. Scripts populate it; a human corrects it
in place; `manifest.json` is **always regenerated from it, never hand-edited**.

```
saijiki source ─┐
                ├─► [stage 1] build spine ──► kigo-2026.csv (word, reading, season, date)
stock photo API ─► [stage 2] fetch+rehost ─► + image_url, image_candidates, attribution
LLM draft ───────► [stage 3] draft desc ────► + description_ja, description_en
                                                     │
                        ┌── HUMAN REVIEW GATE (edit CSV in place) ──┐
                        │  readings · descriptions · image fit/license │
                        └────────────────────────┬────────────────────┘
                                                  ▼
                        [stage 4] assemble ──► Resources/manifest.json (version++)
                        [stage 5] validate ──► ManifestValidationTests + link/license checks
```

Five idempotent, re-runnable stages under `scripts/content/`, each reading/writing
the one CSV. Re-running a stage fills only empty cells (never clobbers human edits)
unless `--force`. Stages are the deterministic engine; the CSV is the human surface.

### External dependencies to stand up

- **Stock-photo API key** — Pexels (free, generous) preferred; Unsplash requires
  download-trigger calls per its license.
- **Static image host** — e.g. Cloudflare R2 / S3 / a GitHub release — serving
  re-hosted images at stable URLs. No server exists today (CONTEXT.md); this is the
  one piece of infra to create.

## Content (text) pipeline

**Stage 1 — build the spine.** One authoritative saijiki source anchors the three
fields that must not be wrong: **kanji, hiragana reading, season/date placement**.
Concrete source TBD at implementation (license permitting): haiku-database kigo
lists, Wikipedia 季語 category, Gabi Greve's WKD, etc. Normalized to
`date, kanji, reading_ja, reading_romaji, season, sekki_hint`.

- **Selection rule:** one kigo per day, ordered by traditional season so the year
  flows spring → summer → autumn → winter → new-year. Over-full seasons down-select
  to the most recognizable words; sparse spans get reviewer-filled gaps. The CSV
  makes the whole year visible at a glance.
- Readings come straight from the source (authoritative); reviewer spot-checks.

**Stage 3 — draft descriptions.** LLM-drafted, grounded in each row's kanji +
reading + season, then human-reviewed:
- `description_ja` — calm 1–2 sentence Japanese gloss.
- `description_en` — English counterpart written natively for an English reader
  (not a literal translation).
- Prompt bakes in the app's quiet, evocative voice (CONTEXT.md): present tense,
  sensory, no haiku clichés.

**Review gate** — a Japanese-literate reviewer reads the CSV top to bottom, fixing
readings and descriptions inline. The one non-automatable step, concentrated into a
single artifact.

## Image pipeline

**Stage 2 — fetch + re-host**, per row:
1. **Query** stock API (Pexels first) with terms derived from the English gloss +
   a curated fallback term (literal kigo names rarely match stock tags). Write the
   top candidate to `image_url` and 2–3 alternates to `image_candidates` so the
   reviewer can swap with one edit instead of re-fetching.
2. **Re-host** the chosen image to the static host under a stable, convention-based
   path keyed by `imageId` (e.g. `…/kigo/2026/kigo-01-01.jpg`). Re-hosting (not
   hot-linking) = stable URLs, controlled dimensions, clean license compliance.
3. **Optimize** — resize to ~1600px long edge, strip EXIF, compress
   (JPEG/HEIC) to ~150–300 KB per image.
4. **Capture attribution** into the CSV → maps straight to `Attribution`
   (photographer/source → credit, license string → license, title → title).

**Schema touch — image URL by convention.** `DailyMapEntry` keeps `imageId` (no
per-row URL). Add a single top-level **`imageBaseURL`** to the manifest (additive,
non-breaking); the app builds the URL as `imageBaseURL + imageId + extension`. Lean
manifest; moving hosts later is a one-line change.

**Image review gate** (same CSV pass): reviewer confirms each image *fits* the kigo
(the one thing scripts can't judge) and that the license is CC0 / Pexels-license /
attribution-only (no editorial-only or model-release traps). Swap = paste an
alternate URL, re-run stage 2 for that row.

## App changes for remote image delivery

Follows the codebase's injectable-seam pattern (protocol + production adapter +
in-memory fake for tests), consistent with `ContentSource` / `EntitlementProvider`.

**New seam — `KigoImageSource`:**
```swift
protocol KigoImageSource: Sendable {
    func image(for imageId: String) async -> KigoImage?   // nil ⇒ caller shows placeholder
}
```
- **Production adapter:** builds URL (`imageBaseURL + imageId`), checks on-disk
  cache, downloads on miss via `URLSession`, writes cache, returns image. Correct by
  inspection; network path stays **off the test gating path** (CLAUDE.md StoreKit
  discipline).
- **Cache:** plain directory cache (URL → file), size-capped LRU. No new dependency.
- **Tests:** inject an in-memory fake returning canned images — verifies
  display/fallback logic headlessly, deterministically, no network.

**Display (app):** `TodayView` shows the existing `KigoPlaceholderView` gradient
immediately, then crossfades to the real image once loaded. Gradient becomes the
loading/offline state — no blank screens, works offline, degrades gracefully.

**Widget:** unchanged — keeps the gradient placeholder. Real photos in the widget
would require pre-fetching into a shared app-group container, reintroducing the
dependency ADR 0019 removed; deferred to a separate future slice with its own ADR.

## Assembly, versioning & validation

**Stage 4 — assemble.** One script reads the reviewed CSV → emits
`Resources/manifest.json`:
- 365 `dailyMap` entries keyed `2026-MM-DD` (kanji, reading, description as
  `LocalizedText` ja+en, `imageId`, `attribution`).
- Existing 72 Kō / 24 Sekki copied through untouched.
- Adds top-level `imageBaseURL`; keeps `schemaVersion`; **bumps `version`** so the
  `RemoteManifestSource` update logic treats it as newer.
- Strips the dummy-data instrumentation (the `(2026-MM-DD)` suffix in descriptions).

**Stage 5 — validate** (fail loudly before ship):
- Existing `ManifestValidationTests` pass (shape, 365 keys, no `02-29`, Kō/Sekki intact).
- New content checks: every `imageId` resolves to a re-hosted object (HTTP 200);
  every entry has non-empty ja+en reading and description; every `attribution` has a
  license string; no leftover `(2026-MM-DD)` debug suffix; no placeholder imageIds.

**Delivery.** Regenerated `manifest.json` bundles as the seed (as today). Future
refreshes can ship as a manifest update + new image objects via the
`RemoteManifestSource` seam **without an app update**; the first real catalog ships
bundled in the next app release for simplicity.

## Deliverables

- `scripts/content/` — 5-stage pipeline; `content/kigo-2026.csv` (reviewed, checked in).
- Regenerated `Resources/manifest.json` — real content + `imageBaseURL`, `version` bumped.
- 365 optimized images on the static host.
- `KigoImageSource` seam + disk cache + crossfade in `TodayView`, with fake-injected tests.
- Widget unchanged (gradient).

## Out of scope

- Refreshing Kō / Sekki content.
- Widget real photos (future slice + ADR).
- Perennial re-keying (ADR 0016 stands).
- Standing up a live content API/backend (only a static object host is required).
- End-to-end remote-manifest fetch on the gating path (existing J7 concern).

## Open items for implementation

- Confirm the specific saijiki source + its license.
- Confirm the static host (R2 / S3 / GitHub release).
- Confirm stock API (Pexels vs Unsplash) and obtain a key.
