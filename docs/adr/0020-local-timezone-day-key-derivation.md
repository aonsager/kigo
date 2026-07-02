# ADR 0020 — Derive "today" in the device's local timezone, not UTC

**Status:** Accepted
**Date:** 2026-07-03
**Supersedes:** the production half of ADR 0006 (UTC day-key derivation)
**Builds on:** ADR 0006 (`DateProvider` seam), ADR 0016 (absolute daily-map keys)

## Context

ADR 0006 introduced `DayKey`, which buckets a `Date` into a perennial `MM-DD` and an
absolute `YYYY-MM-DD` key using a **UTC** Gregorian calendar, "so the same `Date` always
produces the same day-key regardless of the caller's local timezone or test-runner
timezone." That determinism is exactly right for **tests** — but it is wrong in
**production**.

`SystemDateProvider.today` returns `Date()`, a wall-clock *instant*. Bucketing that instant
into a *UTC* calendar day gives the wrong answer for any user whose local day boundary
differs from UTC's. A user in Japan (JST, UTC+9) opening the app any time before 09:00 local
sees the UTC-lagged **previous** day's Kigo: at 00:30 JST on 7/3 the instant is still
15:30 UTC on 7/2, so the app resolved and displayed the 7/2 entry. This is the bug that
prompted the ADR (observed 2026-07-03).

The determinism ADR 0006 wanted was never a *product* requirement — it was a *test* concern.
Tests already control the instant by injecting `FixedDateProvider`; they can equally control
the zone. So the fix is to make the timezone an injectable seam, defaulting to local in
production and pinned explicitly in tests.

## Decision

1. **`DayKey.make` / `DayKey.absolute` take `timeZone: TimeZone = .current`.** They build a
   **Gregorian** calendar pinned to that zone (reusing the cached `utcCalendar` when UTC is
   requested). Production derives the user's *local* calendar day; tests pin an explicit zone
   for determinism.

2. **`Calendar.current` is deliberately NOT used.** It honors the user's calendar *system*
   (a Japanese- or Buddhist-calendar user would get non-Gregorian month/day numbers),
   which would corrupt the Gregorian `MM-DD`/`YYYY-MM-DD` keys the content is keyed by.
   Only the *timezone* is taken from the user; the calendar is always `.gregorian`.

3. **`TodayResolver.resolve` and `AlmanacResolver.resolve` take `timeZone: TimeZone = .current`**
   and thread it into `DayKey`. `AlmanacResolver`'s internal day-within-Kō arithmetic stays
   UTC — it operates on perennial `MM-DD` reference dates and is independent of the user's zone.

4. **The widget resolves in its rollover zone.** `WidgetTimelineBuilder.buildTimeline(calendar:)`
   already computes the next-midnight boundary in the supplied calendar's zone; it now passes
   `calendar.timeZone` to the resolver so the displayed day and the refresh boundary agree.

5. **Fixed `YYYY-MM-DD` string round-tripping stays UTC.** `launchDateProvider` parses
   `KIGO_FAKE_DATE` at noon UTC and re-derives via `DayKey.make(..., timeZone: utcCalendar.timeZone)`
   so the parse and the round-trip check remain self-consistent, independent of the host zone.

## Consequences

- A JST (or any non-UTC) user sees the correct local-day Kigo at all hours. The off-by-one at
  the day boundary is gone.
- Existing unit tests are unaffected: they construct dates at **noon UTC**, which maps to the
  same calendar day in every realistic host zone (UTC−12…UTC+12), so local derivation yields
  the same keys. New tests in `ResolutionTests` pin explicit zones (JST vs UTC) to lock the
  behavior deterministically.
- `DayKey`'s UTC calendar remains the canonical zone for content-string parsing; UTC is no
  longer the derivation zone for "what day is it now."
