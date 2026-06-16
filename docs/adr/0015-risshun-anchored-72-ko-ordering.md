# Risshun-anchored 72-Kō ordering for almanac year-position

## Status
Accepted

## Context
Slice #106 (C11 walking skeleton) introduces `AlmanacPositions`, a value type that
carries the current Kō's 1-indexed position within the almanac year (e.g. 27/72 for
梅子黄 on 06-16). To compute this position, the 72 Kō must be assigned a canonical order.

Two orderings were considered:

1. **Calendar-anchored (01-01)**: sort by `dateRange.start`; the Kō beginning `01-01`
   (雪下出麦) is position 1.
2. **Risshun-anchored (02-04)**: sort by `dateRange.start` then rotate so the Kō
   beginning `02-04` (東風解凍, the first Kō of 立春) is position 1.

## Decision — Risshun-anchored ordering

The 72 Kō are sorted by `dateRange.start` (lexicographic string comparison, which
equals calendar order for zero-padded `MM-DD` strings per ADR 0005), then **rotated**
so the sequence begins at the Kō whose `dateRange.start` is `"02-04"` — the first
microseason of 立春 (risshun, "start of spring").

This rotation is captured in `AlmanacResolver` as a constant:

```swift
private static let risshunStart = "02-04"
```

### Rotation algorithm

```
sortedKo  = manifest.ko.sorted { $0.dateRange.start < $1.dateRange.start }
risshunIdx = sortedKo.firstIndex { $0.dateRange.start == "02-04" }
rotated   = sortedKo[risshunIdx...] + sortedKo[..<risshunIdx]
// rotated[0] is 東風解凍 (02-04 – 02-08)  → position 1
// rotated[26] is 梅子黄 (06-16 – 06-20)   → position 27
```

### Why risshun, not 01-01?

The traditional Japanese almanac's concept of a *new year* is **立春 (risshun)**,
not the Gregorian January 1. The 72 Kō descend from the Chinese lunisolar calendar
(七十二候) in which spring marks the renewal cycle. A year "from risshun" reflects
the domain semantics of the almanac; a year "from January 1" would be an arbitrary
Gregorian overlay on a non-Gregorian concept.

This choice:
- Makes position 1/72 semantically meaningful ("first microseason of spring").
- Aligns the position counter with traditional almanac narrative.
- Is the only anchoring that produces the expected 27/72 result for 梅子黄 on 06-16
  (verified by inspection against the bundled manifest).

Calendar-anchored ordering would yield a *different* position for every Kō in the
first seven weeks of the Gregorian year; risshun-anchored ordering is the correct
domain model.

## Implementation notes

- The sort uses plain `String` comparison, which is correct for zero-padded `MM-DD`
  strings (lexicographic == calendar order). See ADR 0005.
- Containment for finding the *current* Kō reuses the same predicate as `TodayResolver`:
  `dateRange.start <= key && key <= dateRange.end` (see ADR 0008).
- The resolver is a stateless `enum` namespace, Foundation-only, following the pattern
  established by `TodayResolver` in ADR 0007.

## Consequences

- `AlmanacPositions.koYearPosition` is 1-indexed and risshun-anchored. Callers must not
  interpret it as a calendar-year offset.
- The first Kō in the bundled manifest by this ordering is **東風解凍** (position 1,
  `02-04 – 02-08`). The last is **鶏始乳** (position 72, `01-30 – 02-03`).
- Slices #107–#109 (Sekki year-position, day-within-Kō, Kō-within-Sekki) extend
  `AlmanacPositions` additively; this ADR governs only the Kō year-position.
- If the bundled manifest's risshun Kō ever moves (its `dateRange.start` changes),
  `AlmanacResolver.risshunStart` must be updated accordingly. The constant is
  intentionally not derived dynamically from the manifest to keep the resolver
  predictable and auditable.
