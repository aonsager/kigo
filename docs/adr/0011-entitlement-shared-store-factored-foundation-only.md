# ADR 0011 — EntitlementSharedStore factored into a Foundation-only file

**Status:** Accepted  
**Date:** 2026-06-14  
**Slice:** #71 (C7 Slice 3: Entry honours an active entitlement by revealing the image)

## Context

`WidgetTimelineBuilder` needs to read the active-entitlement flag so it can set
`showsImage` on each `KigoWidgetEntry` it produces. The flag lives behind the
`EntitlementSharedStore` protocol, which was previously defined inside
`EntitlementProvider.swift` alongside `StoreKitTransactionSource` and
`EntitlementProvider` — types that `import StoreKit`.

The widget extension (`KigoWidgetExtension`) and its test target (`KigoWidgetTests`)
are wired with an explicit allowlist of Foundation-only files from `Sources/Kigo`
(Manifest.swift, DayKey.swift, DateProvider.swift, TodayResolution.swift,
ContentSource.swift) to avoid dragging SwiftUI and StoreKit into the widget target.

Adding all of `EntitlementProvider.swift` to both widget targets would pull StoreKit
into the widget extension — unnecessary, since the widget only needs the protocol
(and its production `UserDefaultsEntitlementStore` backing, which is pure Foundation).

## Decision

Factor `EntitlementSharedStore` (protocol) and `UserDefaultsEntitlementStore`
(production backing) out of `EntitlementProvider.swift` into a new file:

    Sources/Kigo/EntitlementSharedStore.swift

This file uses only `import Foundation`. It is added to both `KigoWidgetExtension`
and `KigoWidgetTests` source lists in `project.yml`. `EntitlementProvider.swift`
retains `StoreKitTransactionSource`, `StoreKitTransactionSource`, and
`EntitlementProvider`, all of which remain in the `Kigo` app target only.

Both files live in the same Swift module (`Kigo`), so no additional `import`
is needed in `EntitlementProvider.swift` — the types defined in
`EntitlementSharedStore.swift` are visible across the module automatically.

## Consequences

- Widget extension stays free of StoreKit (no unnecessary capability requirement).
- Tests inject an in-memory actor fake conforming to `EntitlementSharedStore` with
  no `SKTestSession` dependency — consistent with the C6 seam-injection pattern.
- `buildEntry()` and `buildTimeline(calendar:)` become `async` to read `isActive`
  from the injected store; callers (and tests) must `await` them.
- The production `TimelineProvider` wiring (slice #73) can inject
  `UserDefaultsEntitlementStore()` at the adapter boundary with no StoreKit call
  in the widget process.
- Adding a new shared-protocol file to `project.yml` follows the established
  per-file allowlist convention (AC4 of the widget test-target wiring slice #69).
