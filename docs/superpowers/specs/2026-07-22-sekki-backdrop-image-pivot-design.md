# Sekki backdrop image pivot — design

**Date:** 2026-07-22
**Status:** Approved (brainstorming) — ready for implementation plan
**Supersedes the image strategy of:** ADR 0022, and the exploratory specs
`2026-07-06-smart-image-selection-design.md` /
`2026-07-06-wikipedia-image-candidate-design.md` (both were attempts to make
per-day image sourcing scale; this pivot abandons that goal).

## Problem

Sourcing a correct, verified image for every one of the 365 Daily Map entries
does not scale. Many Kigo are obscure; for flowers, showing the *right* species
demands per-image verification the maintainer cannot sustain. The per-day image
was also load-bearing in the product: ADR 0019 defines the free **Encounter** as
"the day's beauty — the full-bleed image, the Kigo kanji + reading," so the
sourcing bottleneck blocks the whole content corpus.

## Decision summary

The app pivots from **per-day photography** to a **uniform, bundled, per-Sekki
blurred backdrop**. Five locked decisions:

1. **Uniform, not conditional.** No per-day images and no "some days have a
   photo, some don't" state. Every day gets the same treatment.
2. **Granularity: per Sekki (24).** One backdrop per solar term (~15 days). Maps
   to a unit the resolver already computes; changes noticeably every couple
   weeks; 24 assets is a manageable sourcing job with no per-item verification.
3. **Typography is the hero.** The **Encounter** is redefined to *"the Kigo
   kanji + reading, set in Asagiri Mincho typography, over the current Sekki's
   seasonal wash."* The backdrop is mood/season, not a depiction to defend. The
   free/paid line does not move — *understanding* stays gated.
4. **Bundled, not remote.** The 24 heavily-blurred backdrops ship in the app
   binary (a few hundred KB total). This collapses the entire per-day image
   runtime seam. `RemoteManifestSource` stays for *content* (text) freshness;
   images stop travelling over the wire.
5. **No attribution.** Backdrops are original / CC0 / palette-generated, so the
   `(i)` Attribution panel and all per-image credit metadata are removed
   entirely — one less bit of chrome on the calm Today screen.

## New domain concept — `Sekki backdrop`

Each of the 24 Sekki carries exactly one bundled, heavily-blurred,
palette-matched backdrop image. Today resolves its backdrop purely from the
current **Sekki** (already computed by the resolver for the Almanac) — no per-day
data, no fetch, always present, offline.

- The backdrop is a property of the **season's wash**, keyed off the perennial
  Kō/Sekki data — *not* the Daily Map.
- The Daily Map entry becomes just the Kigo text (kanji + readings). It sheds
  `imageId` and `attribution`.
- The Manifest sheds the top-level `imageBaseURL`.

CONTEXT.md gains a `Sekki backdrop` term and updates **Encounter**, **Widget**,
**Image Attribution / Attribution panel** (removed), and **imageBaseURL /
KigoImageSource** (removed) entries accordingly.

## Architecture — what changes

### Kept and repurposed
`Sources/Kigo/KigoPlaceholder.swift` already bundles a single photo
(`tsuyu.jpg`) and is the shared full-bleed layer for **both** Today and Widget
via `KigoPlaceholderView`. It becomes the home for the backdrop lookup:

- Replace the hardcoded `backgroundImageName = "tsuyu"` + per-`imageId` gradient
  with `backdrop(for: Sekki) -> Image` resolving one of 24 bundled assets.
- `KigoPlaceholderView` takes a `Sekki` (or a resolved backdrop identifier)
  instead of an `imageId` + optional `remoteImage`. The `kigo.image` a11y
  sentinel stays — it now marks the backdrop.
- The 24 backdrop assets are added to the bundle (Asset catalog or `Resources/`).
  Naming convention keys off the Sekki (e.g. its index or kanji id).

### Deleted — remote image seam
- `Sources/Kigo/KigoImageSource.swift` — entire file (transport protocol,
  on-disk LRU cache, URL derivation, decode gate, URLSession adapter).
- `Sources/Kigo/LaunchImageSource.swift` — the `KIGO_FAKE_IMAGE` launch seam.
- In `KigoApp.swift` / `ContentView.swift`: the `imageSource` +
  `imageBaseURLOverride` wiring passed down to `TodayView`.
- In `TodayView.swift`: `@State remoteImageData`, `resolvedRemoteImage`, the
  `.task { imageSource.image(...) }` fetch, and the mutually-exclusive
  `kigo.image.remote` / `kigo.image.placeholder` sentinels (there is only one
  state now — the bundled backdrop).

### Deleted — attribution
- `Sources/Kigo/AttributionPanelView.swift` — entire file.
- In `TodayView.swift`: the `infoEntry` / `info.circle` `(i)` control, the
  `.attribution` sheet case + enum case, and the `info.*` a11y ids.
- `BottomSheetModal.swift`: the `info.panel` modal id.
- `KigoCore/.../Manifest.swift`: `struct Attribution` and
  `DailyMapEntry.attribution`.
- `KigoCore/.../LanguagePreference.swift`: `a11yImageAttribution` + its JA/EN
  strings.

### Deleted — manifest fields
- `Manifest.imageBaseURL`, `DailyMapEntry.imageId`, `DailyMapEntry.attribution`.

### Content-assembly pipeline (`scripts/content/`)
- `csv_parser.py`: drop the `image_id` and six `attribution_*` columns and the
  entry emission of `imageId` / `attribution`.
- `url_deriver.py`: delete (no image URLs).
- `assembler.py` / `assemble.py`: drop `image_base_url` / `--image-base-url` and
  the top-level `imageBaseURL` stamp.
- `validator.py`: drop `imageId`, `attribution.*`, `imageBaseURL`, and URL-
  derivation validation.
- Remove fixtures `empty_image_id.csv`, `missing_attribution_field.csv`.
- Regenerate `Resources/manifest.json`, `content/kigo-2026.example.csv`, and the
  sample CSV without those columns (manifest is always regenerated, never
  hand-edited — ADR 0022 pipeline convention still holds for text).

### Widget
`KigoWidgetView.swift` / `KigoWidgetEntry.swift` / `WidgetTimelineBuilder.swift`:
`showsImage`/`imageId` collapse to a resolved Sekki backdrop. The widget still
renders full-bleed backdrop + Kigo kanji + reading for everyone (ungated —
unchanged intent), with its legibility scrim.

## Tests

- **Delete:** `KigoImageSourceTests`, `KigoImageSourceAdapterTests`,
  `RemoteImageUITests`, `AttributionPanelUITests`, and the attribution
  assertions threaded through `ContentLocalizationCompletenessTests`,
  `LocalizableContentTests`, `LiveLanguageSwitchUITests`, and the widget tests.
- **Add / adapt:**
  - KigoCore (fast lane): a resolver test that every Sekki (all 24) maps to a
    non-nil backdrop identifier, and that a given date → Sekki → backdrop is
    deterministic. Manifest decode tests updated for the slimmer entry shape.
  - `KigoPlaceholderTests`: backdrop selection is deterministic per Sekki
    (replacing the per-`imageId` hue test).
  - UI: `kigo.image` renders full-bleed for any pinned date; Basic user still
    sees the backdrop (adapt C22's `TodayScreenUITests`); Widget renders the
    backdrop ungated.
- **Fast lane first**, always (`swift test --package-path KigoCore`); sim lane
  for the Today/Widget UI adaptations.

## GOAL.md amendment

This repo is goal-driven by the afk loop. This pivot **changes the goal**, so
several already-satisfied criteria are legitimately retired. The amendment must
be explicit so completeness accounting reads as an intentional goal change, not
a regression.

- **Delete:** **C12** (attribution content), **C14** (attribution panel),
  **C25** (`KigoImageSource` seam/cache/fallback), **C26** (remote image +
  placeholder fallback), **J10** (real per-day images from CDN).
- **Rewrite (image → Sekki backdrop; drop imageId/attribution clauses):**
  - **C2** — drop the `imageId` dataset assertion.
  - **C5 / C18 / C22** — `kigo.image` stays full-bleed but is now the Sekki
    backdrop, not a per-day photo.
  - **C7 / J3** — Widget reveals the backdrop + Kigo; drop `imageId`.
  - **C19** — drop the per-entry attribution-bilingual clause (Kigo/Kō/Sekki
    text localization stays).
  - **C24** — pipeline no longer validates `imageBaseURL`/`imageId`/
    `attribution` or derives image URLs.
  - **J1 / J2** — reword to the new thesis: a calm moment *dominated by the word
    over a seasonal wash*; J2's "imagery accurate + real attribution" collapses
    to "the 24 backdrops evoke their season." The per-item verification burden is
    **deleted, not moved**.
- **Keep unchanged:** **J5** (no lock badge on the image).

## ADRs

- **New ADR** — "Uniform per-Sekki bundled backdrops; retire per-day remote
  images." Supersedes **0022**; records the five decisions above and the reason
  (per-day sourcing/verification does not scale).
- **Amend 0019** — the Encounter's definition (image → word-over-wash); the
  free/paid line is unchanged.
- **0014** — note the `Attribution` schema is retired; leave the ADR as history.

## Out of scope

- Actually sourcing/creating the 24 backdrop images (a maintainer content task;
  the plan ships the resolver + bundling + a placeholder set so the code lands
  green, with real art dropped in later).
- Any change to the RemoteManifestSource *content* update path — text freshness
  is unaffected.
- Any change to the Understanding layer, Almanac, paywall, or entitlement logic.

## Success criteria

- Today and Widget render a full-bleed Sekki backdrop resolved from the current
  Sekki, with the Kigo kanji + reading as the visual hero — offline, instant, no
  fetch, for every date in range.
- The manifest, CSV schema, and pipeline carry no image/attribution fields.
- Fast lane green; the adapted UI suite green.
- GOAL.md and CONTEXT.md reflect the new Encounter and the retired criteria;
  the superseding ADR is committed.
