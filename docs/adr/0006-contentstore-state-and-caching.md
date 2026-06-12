# ContentStore state-enum shape, cache/store ownership model, and C3↔C4 boundary

## Status
Accepted

## Context
Slice #18 introduces the `ContentSource` protocol and `BundledContentSource`. Before the ContentStore itself is implemented (slices #19–#21), three design decisions must be recorded to constrain those slices and prevent scope creep into C4 territory:

1. The state-enum shape that ContentStore will expose.
2. How caching is owned and managed.
3. What belongs in C3 vs. what is deferred to C4.

## Decision 1 — ContentStore state-enum shape

The ContentStore will expose its state as an enum with three cases:

```swift
enum ContentState: Sendable {
    case loading
    case loaded(Manifest)
    case unavailable(Error)
}
```

Rationale:
- `loading` is the initial state and covers any in-flight fetch. There is no separate "not started" case; the store begins loading on initialisation.
- `loaded(Manifest)` carries the decoded manifest directly so consumers can access it without an optional unwrap.
- `unavailable(Error)` replaces a bare `.failed` so the UI can surface a meaningful error message (bundle missing, decode error, etc.) without re-throwing.
- The enum is `Sendable` because `Manifest` is already `Sendable` and `Error` is protocol-typed; concrete errors stored in this case must also be `Sendable`.

## Decision 2 — Cache and store ownership model

- **ContentSource is stateless**: every call to `load()` performs a fresh decode from the bundle. It holds no cache and carries no mutable state.
- **ContentStore owns the in-memory cache**: the store calls `ContentSource.load()` once (or on explicit refresh) and caches the result as the `.loaded(Manifest)` associated value. Subsequent reads are served from the cached state without re-decoding.
- **No disk persistence in C3**: the cache is purely in-memory and is not written to disk. App re-launch triggers a fresh bundle decode, which is fast enough for a bundled resource. Disk persistence (e.g. for a future HTTPContentSource) is a C4+ concern.
- **Ownership**: `ContentStore` is an `@Observable` class (a single instance, owned by the app root) injected into the SwiftUI environment. It conforms to no caching protocol; the in-memory cache is an implementation detail.

## Decision 3 — C3↔C4 resolution boundary

**C3 scope (this and following C3 slices):**
- `ContentSource` protocol and `BundledContentSource` (slice #18, this slice).
- `ContentStore` with state machine and in-memory cache (slices #19–#21).
- A **minimal day-key lookup** `dailyMap["MM-DD"]` via an injectable `DateProvider` (protocol returning today's date as a `Date`). This is sufficient to answer "what is today's Kigo?" using the pre-computed Daily Map, without any Kō/Sekki resolution logic.

**C4 scope (explicitly deferred — do NOT build in C3):**
- Full Microseason resolution: mapping a date to its current active Kō and parent Sekki.
- Boundary-day handling: days where two Kō meet at sunrise, handling of the exact transition moment.
- Seasonal display logic: computing which Sekki window is active, how many days until the next Kō transitions.
- Any `HTTPContentSource` or live-network path.

The C3/C4 boundary is drawn at the Daily Map: C3 reads `dailyMap["MM-DD"]` directly. The 72 Kō `dateRange` fields and the 24 Sekki are present in the manifest and must not be stripped, but the resolution algorithm that interprets them is C4.

## Consequences
- Slices #19–#21 implement `ContentStore` with the state enum above; they do not need to revisit this shape.
- The `DateProvider` injection point in C3 keeps the day-key lookup unit-testable without mocking the system clock.
- C4 can build Microseason resolution on top of the already-loaded `Manifest` without changing `ContentSource`, `ContentStore`, or the JSON schema.
