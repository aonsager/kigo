# ADR 0026 — Uniform per-Sekki bundled backdrops

**Status:** Accepted
**Date:** 2026-07-22
**Supersedes:** ADR 0022 (content-assembly pipeline and remote image delivery — the image-delivery half; the text pipeline stands)
**Relates to:** ADR 0001 (ContentSource seam / placeholder imagery), ADR 0014 (the
`Attribution` schema — retired here), ADR 0016/0018 (absolute 2026 Daily Map, localized
content), ADR 0019 (Encounter vs Understanding — the Encounter's composition is amended
here), ADR 0024 (`translationEn` free-Encounter field).
Design brief: `docs/superpowers/specs/2026-07-22-sekki-backdrop-image-pivot-design.md`.

## Context

ADR 0022 committed to sourcing a real, verified photograph for every one of the 365 Daily
Map entries, delivered by remote URL + on-device cache, with per-image attribution
metadata. That does not scale: many kigo are obscure, and for flowers in particular showing
the *right* species demands per-image verification the maintainer cannot sustain across 365
entries. The per-day image was also load-bearing in the product, not merely decorative: ADR
0019 defined the free **Encounter** as "the day's beauty — the full-bleed image, the Kigo
kanji + reading," so the sourcing bottleneck blocked the whole content corpus, not just its
imagery.

## Decision

**Pivot from per-day photography to a uniform, bundled, per-Sekki blurred backdrop.
Supersedes ADR 0022.** ADR 0022's content-assembly pipeline stands for *text*; only its
image-delivery half (remote URL + cache + attribution) is superseded. Five locked decisions:

1. **Uniform, not conditional.** No per-day images and no "some days have a photo, some
   don't" state. Every day gets the same treatment — one code path, no conditional image
   state.
2. **Granularity: per Sekki (24).** One backdrop per solar term (~15 days) — a unit the
   resolver already computes for the Almanac. It changes noticeably every couple of weeks,
   and 24 assets is a manageable sourcing job with **no per-item verification**.
3. **Typography is the hero.** The **Encounter** is redefined to *"the Kigo kanji + reading,
   set in Asagiri Mincho typography, over the current Sekki's seasonal wash."* The backdrop
   is mood/season, not a depiction to defend. The free/paid line does not move —
   *understanding* stays gated (ADR 0019, unchanged).
4. **Bundled, not remote.** The 24 heavily-blurred backdrops ship in the app binary (a few
   hundred KB total). This collapses the entire per-day image runtime seam.
   `RemoteManifestSource` stays for *content* (text) freshness; images stop travelling over
   the wire.
5. **No attribution.** Backdrops are original / CC0 / palette-generated, so the `(i)`
   Attribution panel and all per-image credit metadata are removed entirely — one less bit
   of chrome on the calm Today screen.

**New domain concept — `Sekki backdrop`.** Each of the 24 Sekki carries exactly one bundled,
heavily-blurred, palette-matched backdrop image, resolved purely from the current **Sekki**
(`SekkiBackdrop.assetName(forSekkiId:) -> "backdrop-<id>"`) — no per-day data, no fetch,
always present, offline. Until the real 24 assets are supplied out-of-band, the shared
`KigoPlaceholderView` falls back to a deterministic per-Sekki gradient wash
(`SekkiBackdrop.fallbackHue(forSekkiId:)`); the `kigo.image` accessibility id stays the
sentinel, now marking the backdrop instead of a per-day photo.

**Deleted:**
- The `KigoImageSource` remote seam in its entirety — transport protocol, on-disk LRU
  cache, URL derivation, decode gate, `URLSession` adapter — and `LaunchImageSource`
  (`KIGO_FAKE_IMAGE`).
- The `(i)` Attribution panel — `AttributionPanelView`, `info.entry`/`info.panel`, and the
  `a11yImageAttribution` strings.
- The manifest model fields `DailyMapEntry.imageId`/`DailyMapEntry.attribution` (and the
  `Attribution` struct) and `Manifest.imageBaseURL`.
- From the content-assembly pipeline (`scripts/content/`): the `image_id`/`attribution_*`
  CSV columns, `url_deriver.py`, and the `imageBaseURL`/`--image-base-url` stamping in
  `assembler.py`/`assemble.py`.

## Consequences

- **The entire remote-image seam is gone.** No CDN, no on-disk image cache, no
  `KIGO_FAKE_IMAGE` launch seam, no loaded/fallback distinction to gate — the Today screen
  and Widget render the bundled backdrop (or its gradient-wash placeholder) unconditionally.
- **The Attribution panel and its schema are gone.** The `(i)` control, its sheet, and the
  `Attribution` struct ADR 0014 introduced are retired; ADR 0014 is amended with a pointer
  to this ADR rather than rewritten (its body stays accurate as history).
- **Typography becomes the Encounter's hero.** ADR 0019 is amended: the Encounter's
  composition moves from *image + word* to **word-over-wash**; the free/paid line itself is
  unchanged — understanding stays the only gated thing.
- **Can't hot-swap backdrop art without an app update.** Bundling trades runtime
  flexibility for simplicity — acceptable for 24 aesthetic, non-per-day assets that change
  on no fixed schedule (unlike daily content, which still updates via
  `RemoteManifestSource`).
- **`scripts/content/fill/` is rendered obsolete, not patched.** The content-fill tooling
  (`fetch_images`, the Wikipedia image-candidate ladder, and the review UI's
  image-candidate columns/picker — see ADR 0025) was built entirely around sourcing and
  reviewing a *per-day* image, and now breaks against the new, image-free assemble
  contract (`assemble.py` no longer accepts `--image-base-url`, and the CSV it reads has no
  image columns to feed). This is a **known follow-up requiring its own rethink** — either
  the fill workflow's job shrinks to text-only spine/reading/prose authoring, or its review
  surface is repurposed for backdrop curation — not something a column patch fixes, and it
  is explicitly **not** undertaken by this ADR.
- **GOAL.md criteria change.** C12, C14, C25, C26, and J10 are retired (marked, not
  silently deleted — see the RETIRED markers in `docs/GOAL.md`); C2, C5, C7, C18, C19, C22,
  and C24 are rewritten to drop `imageId`/`attribution`/remote-image language in favor of
  the Sekki backdrop; J1, J2, and J3 are reworded to the new thesis; J5 is unchanged.

**2026-07-23 update.** The `scripts/content/fill/` follow-up flagged above has been
resolved: rather than repurposing its review surface for backdrop curation, the tool is
descoped to a text-only editorial review tool. Image sourcing (`fetch_images.py`, the
Pexels/Pixabay/Wikipedia candidate ladder, the review UI's candidate gallery,
`--image-base-url`) is removed entirely; `review.db` gets an automatic, version-guarded
v0→v1 migration that drops the `candidates` table and `chosen_candidate_id` column while
preserving every `days` row; and the tool's CSV output is repaired to the 7-column contract
(`date, kanji, reading_ja, reading_en, translation_en, description_ja, description_en`)
this ADR's `assemble.py` change already expects. See plan
`docs/superpowers/plans/2026-07-23-content-fill-text-only-editorial.md`.
