# ADR 0021 — Widget-gallery chrome is localized by device locale via a String Catalog

**Status:** Accepted
**Date:** 2026-07-03
**Relates to:** ADR 0018 (in-app JP/EN toggle drives every string), ADR 0004/0012 (widget extension)

## Context

The goal requires **every user-facing string to be localized**. Almost all of them are
driven by the in-app language preference: content via `LocalizedText.localized(for:)`
and UI chrome via `ChromeStrings(preference)` (ADR 0018) — pure Swift, no String
catalogs, switchable live from Settings.

One surface cannot use that seam: the **widget gallery** entries set on the
`WidgetConfiguration` — `configurationDisplayName("Kigo")` and
`description("Today's seasonal word.")`. These are rendered by the **system** (in the
widget picker / gallery), before the extension runs, with no access to the app's
`LanguageStore`. WidgetKit resolves them from the extension bundle's localizations
keyed on the **device locale**. There is no pure-Swift way to localize them; the
`.description(...)` literal is already a `LocalizedStringKey` that WidgetKit looks up
in the bundle.

The widget's *content* remains Japanese-only by design (CLAUDE.md / ADR 0012 — the
widget never calls `localized(for:)`). Only its **gallery chrome** is in question here.

## Decision

**Localize the widget gallery description with a String Catalog resolved by device
locale — a deliberate, scoped carve-out from the "no String catalogs" convention.**

- Add `Sources/KigoWidgetExtension/Localizable.xcstrings` (source language `en`) with
  the `ja` translation of `"Today's seasonal word."` → `"今日の季語。"`.
- Advertise both localizations on the extension bundle via `CFBundleLocalizations`
  (`en`, `ja`) in the widget `Info.plist`, and `CFBundleDevelopmentRegion = en`, so the
  `ja` value resolves on ja-locale devices independent of XcodeGen's region inference.
- `configurationDisplayName("Kigo")` is a **brand name** — identical in both languages,
  so it carries no translation (the same reason kanji subject-matter is never
  translated, ADR 0018).

## Why not the in-app `ChromeStrings` seam

The gallery is drawn by the OS outside the extension process; there is no environment,
no `LanguageStore`, and no view tree to read `@Environment(\.language)` from. The device
locale is the only signal available, so a bundle-localized String Catalog is the only
mechanism. This does **not** reopen ADR 0018 for the in-app UI — that stays pure-Swift
and toggle-driven.

## Consequences

- Introduces the project's first String Catalog. It is confined to the widget extension
  and to system-drawn gallery chrome; the app and the widget's own rendered content keep
  the in-app-toggle approach.
- The gallery description now follows the **device** language, which may differ from the
  in-app language preference. This is correct for a system surface — the two are
  independent by construction.
- XcodeGen auto-adds `ja` to `knownRegions` from the catalog, so the String Catalog
  compiler emits the `ja` localization into the bundle (verified in the built `.appex`).
- Runtime gallery rendering per device locale is a system behavior not exercised by the
  headless test lanes; it is verified by build (the `ja` localization lands in the
  bundle) and by inspection, not by an automated gating test.
