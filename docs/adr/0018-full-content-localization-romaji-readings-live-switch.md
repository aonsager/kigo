# ADR 0018 — Full JP/EN content localization, romanized readings, and live language switching

**Status:** Accepted
**Date:** 2026-06-21
**Criteria:** C19, C20
**Extends:** ADR 0014 (localization-ready schema; English content was deferred there)

## Context

ADR 0014 made the schema localization-*ready* (required `ja`, optional `en`) but **deferred
populating English** and switched only **UI-chrome** strings (C15). The goal now brings full
JP⇄EN content localization into scope, with two specific decisions from the goal session:

1. **Readings are romanized in English mode** — not just prose. In Japanese mode a reading shows
   its hiragana; in English mode it shows romaji.
2. **Switching language is live** — toggling JP/EN in the Settings menu must re-render every
   visible string immediately, with **no relaunch** (the existing `KIGO_FAKE_LANGUAGE` only pins
   the *initial* value).

## Decision

**Populate English across the manifest, migrate readings and the Daily-Map description to the
localized shape, and drive the UI from an observable language store so a switch re-renders live.**

- **Schema migration (bump `schemaVersion`):** `DailyMapEntry.description`,
  `DailyMapEntry.reading`, `Ko.reading`, and `Sekki.reading` migrate from `String` to
  `LocalizedText` (`ja` + `en`). For readings, `ja` = hiragana, `en` = romaji. Existing
  `LocalizedText` fields (Kō/Sekki `description`, Sekki `gloss`, attribution) gain populated `en`.
- **Kanji names never translate.** `kanji` stays a single `String` on every type, shown
  identically in both languages (content identity, per CONTEXT.md).
- **Live switching:** a published **language store** (the persisted Language preference) is the
  single source of truth the Today screen, Almanac, Attribution panel, and chrome observe;
  changing it republishes and SwiftUI re-renders — no relaunch, no re-fetch.
- **Selection accessor:** a small `localized(_:)` accessor resolves a `LocalizedText` to the
  active language, falling back to `ja` when `en` is missing (forward-compatible with partial
  English, preserving ADR 0014's decode-with-or-without-`en` guarantee).

## What is gated vs not

- **Gated (C19):** every Daily-Map entry, Kō, and Sekki carries a non-empty `en` for its
  localized prose/reading fields, and the manifest still decodes with or without `en` present.
- **Gated (C20):** in the running app, toggling the Settings switcher flips content **and** chrome
  from Japanese to English **without relaunch** (kanji unchanged), verified via UI test.
- **Not gated:** translation quality / romaji style and tone — judgment claim J2.
- **Still out of scope:** region/number/date *locale formatting* — only language strings switch.

## Consequences

- C15 (chrome switching, persisted preference, switcher control) is unchanged and still holds;
  C19/C20 are additive and extend it to content + live reactivity.
- Tests that hand-build manifest fixtures must now supply `LocalizedText` for readings and the
  Daily-Map description; the generator emits both languages.
- Risk: a string rendered from a non-observed copy of the preference would not update live.
  Mitigated by routing all language reads through the single published store (C20 catches a
  missed surface — a string that fails to flip on toggle fails the test).
