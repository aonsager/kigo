# Today-resolution result type, resolver location, and shared day-key derivation

## Status
Accepted

## Context
Slice #30 introduces the first end-to-end resolution path: an injected date flows through
a day-key derivation into a Daily Map lookup and out as a typed result. Three design
decisions needed to be made and recorded before the implementation could be locked:

1. The shape of the resolved result type.
2. Where the resolver lives relative to `ContentStore`.
3. How the `MM-DD` day-key derivation is shared between `ContentStore` and the resolver.

## Decision 1 — Resolved result type: `ResolvedDay`

```swift
public struct ResolvedDay: Sendable, Equatable {
    public let kigoEntry: DailyMapEntry
    // Slice #32 will add:
    //   public let ko: Ko
    //   public let sekki: Sekki
}
```

**Name**: `ResolvedDay` — describes what has been resolved ("a day") rather than the act
of resolving (avoiding `Resolution` as a verb-noun that reads ambiguously).

**Shape**: A plain `struct` carrying only `kigoEntry: DailyMapEntry` in this slice.
The comment documents the extension point for slice #32 (which will add `ko` and `sekki`).
Adding those fields in #32 is source-compatible because `ResolvedDay` is returned
(not accepted as a parameter), so new fields with default-free initializers are additive.

**Foundation-only**: No SwiftUI import; the type is safe to use from the test target
and from any future non-UI layer.

## Decision 2 — Resolver location: `TodayResolver` enum in `TodayResolution.swift`

The resolver is a **stateless enum namespace** (`public enum TodayResolver`) with one
static method:

```swift
public static func resolve(date: Date, manifest: Manifest) -> ResolvedDay?
```

Rationale:
- **Separate from `ContentStore`**: `ContentStore` is an `@Observable` class bound to
  `@MainActor` with SwiftUI lifecycle concerns. The resolver is pure and Foundation-only.
  Mixing them would force the resolver to carry actor isolation unnecessarily.
- **Free function vs. enum namespace**: A bare free function is equally valid, but
  Swift convention for a set of related static functions is a caseless enum or a struct
  with no stored properties. `enum` is preferred over `struct` here because a struct can
  accidentally be instantiated; `enum` with no cases cannot.
- **Relationship to `ContentStore`**: `ContentStore.todayEntry()` remains the SwiftUI-facing
  entrypoint. `TodayResolver.resolve(date:manifest:)` is the pure logic underneath. In C5
  (the Today screen), the UI can use either path — `ContentStore` is the natural choice
  because it already manages the cache and observable state.

## Decision 3 — Shared day-key derivation: `DayKey` enum in `DayKey.swift`

```swift
public enum DayKey {
    static let utcCalendar: Calendar = { /* UTC Gregorian */ }()

    public static func make(from date: Date) -> String?
}
```

Before this slice, `ContentStore` had a `private static let utcCalendar` and inlined
the `String(format: "%02d-%02d", month, day)` formatting. This was the only implementation.
The acceptance criterion for slice #30 requires ONE implementation feeding BOTH
`ContentStore` and the new resolver.

**Approach**: extract into `DayKey.make(from:)`. Both `ContentStore.todayEntry()` and
`TodayResolver.resolve(date:manifest:)` delegate to this function. The UTC calendar is
defined once in `DayKey.utcCalendar` and reused as a `static let`.

**Why not an extension on `Date` or `Calendar`?** A free-standing `DayKey` type is
self-documenting (the name tells callers exactly what it produces) and keeps the UTC
contract explicit. An extension on `Date` could be confused with other date-formatting
utilities.

## Consequences

- `ContentStore.todayEntry()` is simplified: it calls `DayKey.make(from:)` instead of
  maintaining its own UTC calendar and format string.
- `TodayResolver.resolve(date:manifest:)` is pure and easily tested with `FixedDateProvider`.
- Slice #31 (Kō resolution by date-range containment) and slice #32 (full three-part result)
  can extend `ResolvedDay` and reuse `DayKey` without touching the manifest schema.
- `ContentStore` keeps its existing test suite green because its public API (`todayEntry()`)
  is unchanged — only the private implementation was refactored.
