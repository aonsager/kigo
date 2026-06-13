# Kō containment logic lives in `TodayResolver`, uses plain string comparison

## Status
Accepted

## Context
Slice #31 requires resolving the current Kō — the single one of the 72 whose
`dateRange` contains the date's `MM-DD` key. Two design choices needed recording:

1. **Where does the containment logic live?**
2. **How is containment defined?**

## Decision 1 — Containment logic in `TodayResolver.resolve(date:manifest:)`

The `first(where:)` scan over `manifest.ko` is inlined into the existing resolver
function rather than extracted into a separate helper or a method on `Ko`/`DateRange`.

Rationale:
- **Single call site**: Only the resolver needs to search Ko by date. There is no
  second caller that would benefit from a shared helper.
- **Keeps the module shallow**: Adding a method to `DateRange` or `Ko` (neither of
  which owns the resolution concern) would scatter logic across types for no gain.
- **Defer until duplication arises**: If slice #32 (Sekki resolution) or a future
  slice introduces a second containment query, extraction becomes justified then.

## Decision 2 — Containment is `start ≤ key ≤ end` with plain `String` comparison

The manifest schema (ADR 0005) stores `dateRange` as `MM-DD` strings, with ranges
that are contiguous, non-wrapping (i.e. `start ≤ end` always holds), and tile the
full calendar year. Given those invariants, containment reduces to:

```swift
ko.dateRange.start <= key && key <= ko.dateRange.end
```

Standard lexicographic `String` comparison is correct because the `MM-DD` format
zero-pads both fields, so lexicographic order equals calendar order.

**No year-wrap logic**: ADR 0005 explicitly rules out wrap-around ranges. The tiling
uses a linear-year model; the special Ko that straddles the year boundary (雪下出麦,
01-01 – 01-04, and 鶏始乳, 01-30 – 02-03) are expressed with normal start ≤ end
ranges and do not require wrap-around handling.

## Consequences

- `TodayResolver.resolve` returns `nil` if no Ko contains the derived key.
  This is consistent with the existing nil-on-missing-entry behavior for `dailyMap`.
- The `ResolvedDay` struct gains a non-optional `ko: Ko` field; callers that
  previously destructured `ResolvedDay` must be updated (there is only one
  instantiation site: `TodayResolution.swift` itself).
- Slice #32 (Sekki resolution) follows the same pattern: add `sekki: Sekki` to
  `ResolvedDay` and resolve it inside the same `resolve` function.
