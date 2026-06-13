# ADR 0009: EntitlementProvider owns the StoreKit entitlement seam

## Status

Accepted (C6 slice 1, issue #38)

## Context

The app gates widget features behind an auto-renewable subscription
(`com.tomeitotameigo.kigo.widgets.monthly`). Multiple consumers need to know whether
the user is currently entitled: the app UI (Paywall/gate logic) and the Widget Extension.
StoreKit's transaction API is async and requires verification; callers should not deal
with those details directly.

## Decision

Introduce `EntitlementProvider` as a **deep module** (small public interface, deep
StoreKit implementation) in `Sources/Kigo/`. Its public surface is a single
`async -> Bool` method: `isEntitlementActive()`. It owns all StoreKit interaction:
iterating `Transaction.currentEntitlements`, verifying results, and matching the
product ID.

The StoreKit testing layer uses `Kigo.storekit` (committed to the repo) as the
configuration for `SKTestSession` in `KigoTests`. The StoreKitTest framework is linked
only to the test target, not the app target. The `.xcodeproj` remains gitignored per
ADR 0003; `project.yml` is the sole source of truth for project structure.

## Consequences

- Callers (UI, Widget) depend only on a Boolean; they are never exposed to StoreKit types.
- Tests drive entitlement state by controlling `SKTestSession` — no App Store Connect
  setup, no sandbox accounts, fully deterministic.
- Later slices can extend `EntitlementProvider` (purchase, restore, shared-store write)
  without changing the call sites that only need `isEntitlementActive()`.
- The seam is not injectable as a protocol in this slice (only inactive read is needed).
  If future slices require injecting a fake entitlement state into the UI, a protocol
  can be extracted at that point.
