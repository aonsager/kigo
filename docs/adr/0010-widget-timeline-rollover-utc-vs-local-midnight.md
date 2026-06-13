# Widget timeline rollover: entry activation at local midnight, content keyed by UTC

## Status
Accepted

## Context
Slice #70 extends `WidgetTimelineBuilder` to return a two-entry timeline. The second entry
must activate at the next local midnight (so WidgetKit advances the widget at the correct
moment for the user) and carry the Kigo content for "tomorrow".

Two timescales are in play:

1. **Entry activation date** — the `Date` stored in `KigoWidgetEntry.date`. WidgetKit uses
   this instant to decide *when* to swap the widget view. It must be the next local midnight
   in the device's timezone so the widget flips at the start of the new calendar day for the
   user, not at 00:00 UTC (which would be wrong in every non-UTC timezone).

2. **Content resolution date** — the `Date` passed to `TodayResolver.resolve(date:manifest:)`,
   which delegates to `DayKey.make(from:)` (UTC). The MM-DD key derived from this date
   determines which Kigo is shown.

The fundamental tension: `DayKey.make` uses UTC, but "tomorrow" for the user is defined in
their local timezone. The activation instant (next local midnight) and the "correct" UTC date
for tomorrow's content can disagree for large positive offsets (UTC+12 to UTC+14). For
example, at UTC+13, midnight local = 11:00 UTC the *previous* UTC day, so
`DayKey.make(nextLocalMidnight)` returns the current UTC day's key, not the next one.

## Decision

**Use next local midnight as both the activation date and the content-resolution date.**

Concretely: `WidgetTimelineBuilder.buildTimeline(calendar:)` accepts an explicit `Calendar`
(defaulting to the device's local `Calendar.current`) so the "next midnight" computation is
deterministic in tests. The local calendar's `.startOfDay` on `today + 1 day` gives next
local midnight. That instant is passed to `TodayResolver` for content resolution.

This means the second entry's content is governed by `DayKey.make(nextLocalMidnight)`, which
uses UTC. For timezones where midnight-local falls on the same UTC day as the current moment
(extreme positive offsets, UTC+12..UTC+14), the content may transiently match the current
day's Kigo rather than the user's "tomorrow". This is accepted because:

- **Existing code already carries this trade-off.** `DayKey` is deliberately UTC (ADR 0006)
  for determinism. The existing first entry already has this property. Introducing a second
  date system only for the rollover entry would create an inconsistency harder to reason about
  than a rare near-identical content window for extreme UTC+ users.

- **The boundary is self-correcting.** Once the activation instant arrives (midnight local),
  WidgetKit calls `getTimeline` again and recomputes from the new "today". Any transient
  mismatch lasts at most until the widget re-timeline (which WidgetKit does at the activation
  date anyway).

- **Testability wins.** Injecting a `Calendar` (explicit timezone) keeps tests deterministic
  regardless of the test-runner's timezone. UTC-based tests can verify exact midnight
  boundaries without depending on the host machine's locale.

The production `KigoWidgetProvider` (slice #73) will pass `Calendar.current` for the correct
device timezone. Tests inject `Calendar` with `UTC` timezone for full determinism.

## Consequences

- `WidgetTimelineBuilder` gains a `buildTimeline(calendar:)` method. `buildEntry()` is kept
  for backward compatibility with slice-#69 tests.
- The new method is pure (no real clock, no network) and directly unit-testable.
- Tests construct dates using UTC calendar and inject a UTC calendar for "next midnight"
  computation, so assertions are exact and timezone-independent.
- The `KigoWidgetProvider.getTimeline` in slice #73 will call `buildTimeline(calendar: .current)`.
