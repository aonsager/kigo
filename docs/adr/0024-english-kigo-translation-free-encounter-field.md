# ADR 0024 — English kigo translation as a free-Encounter content field

**Status:** Accepted
**Date:** 2026-07-06
**Relates to:** ADR 0014 (optional-field forward-compat), ADR 0018 (full content
localization / romaji readings), ADR 0019 (Encounter vs Understanding monetization
split, Meaning Gate), ADR 0022 (content-assembly pipeline).

## Context

Each Daily Map entry carries the Kigo's `kanji`, a bilingual `reading` (JP kana /
EN romaji), and a bilingual `description`. A Japanese reader comprehends the day's
word directly from the **kanji** — that comprehension is part of the free
**Encounter**. An English reader, by contrast, sees only the kanji plus a romaji
reading (e.g. 花見 · *hanami*) and understands nothing of what the word *is*.

We want to add a short English translation/name of the word itself (花見 →
"cherry-blossom viewing"), distinct from the longer significance prose, and decide
(a) where it lives in the model/Contract, (b) whether it is free or paid, and
(c) when it renders.

## Decision

1. **Model.** Add `translationEn: String?` to `DailyMapEntry` — an English-only
   plain string, **not** a `LocalizedText` (the word has no "translation" into
   Japanese; a Japanese reader uses the kanji). Optional, following the ADR 0014
   additive-forward-compat pattern (`LocalizedText.en`, `Manifest.imageBaseURL`):
   manifests without the key still decode, and **no `schemaVersion` bump** is
   implied. An explicit memberwise init defaults it to `nil` so existing
   construction sites (many test fixtures) compile unchanged.

2. **Free Encounter, not paid Understanding.** The translation is shown to
   **everyone**, alongside kanji + reading, outside the Meaning Gate. Rationale:
   it is the English reader's equivalent of being able to read the kanji — it
   *names* the word; it is not the significance prose. The paid Understanding (the
   full `description`, the Microseason, the Almanac) stays gated. This keeps the
   free tier coherent across languages rather than leaving English Basic users
   with an opaque screen.

3. **English mode only.** It renders only when the Language preference is English.
   In Japanese mode it is hidden (an English gloss beside the kanji would be
   redundant and off-register on an otherwise all-Japanese screen). Accessibility
   id `kigo.translation`.

4. **Required content going forward.** Although the Swift field is optional for
   decode-compat, real content must always carry it: the CSV column
   `translation_en` is required (`csv_parser`/`validator` reject a blank one),
   the fill workflow authors it (LLM, seeded by the source's short name), and a
   completeness test asserts a non-empty, CJK-free `translationEn` on every
   bundled entry. Same posture as `LocalizedText.en` (optional in Swift, required
   in content via completeness tests).

## Consequences

- The Contract gains a field. Because it is additive/optional, the
  RemoteManifestSource comparison, the widget (which never reads it — the widget
  Encounter stays image + kanji + reading), and all existing fixtures are
  unaffected.
- The bundled **dummy** manifest is back-filled by the idempotent
  `scripts/add_translation_en.py` (deriving a label from the existing dummy
  English description) until the real catalog (ADR 0022 fill workflow) replaces
  it; real content emits `translationEn` through `assemble.py`.
- Monetization surface is unchanged in spirit: *understanding the day* remains the
  paid line; *reading the word* is free in both languages.
