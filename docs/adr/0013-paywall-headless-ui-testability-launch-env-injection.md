# ADR 0013 — Paywall headless UI-testability via launch-environment-injected fakes

**Status:** Accepted
**Date:** 2026-06-15
**Criteria:** C9 (Paywall reachable + compliant offer), C10 (purchase logic)

## Context

The Paywall (C9) must be verified through the **real** live app — that it is
actually constructed and reachable from the Today screen, not merely that a
`PaywallView` type exists (it already existed, fully unreachable, before this work).
That means a `KigoUITests` test that launches the app and taps the Upgrade entry.

But the Paywall's appearance depends on two things that, in production, come from
live StoreKit and therefore cannot be driven headlessly (ADR 0009):

1. the user's plan (**Basic** vs **Premium**) — which decides buy-offer vs manage
   state, and is derived from the live `Transaction.currentEntitlements`;
2. the displayed **price + duration** — which in production is loaded from a real
   `Product` via App Store Connect.

A UI test cannot wait on either: real entitlement loading needs an account, real
product loading needs the network/App Store. The existing app already solves the
analogous problem for *date* by reading a `KIGO_FAKE_DATE` launch-environment
variable at startup (`launchDateProvider(environment:)`, ADR-less convention from
slice #56) and pinning a `DateProvider` when present.

## Decision

**Extend the `KIGO_FAKE_*` launch-environment convention to the Paywall's StoreKit
seams, so the live app under UI test is driven entirely by deterministic injected
fakes — no `storekitd`, no network, no account.**

At app startup, mirror `launchDateProvider`:

- `KIGO_FAKE_ENTITLEMENT=active|inactive` → build an `EntitlementProvider` over an
  in-memory fake `EntitlementTransactionSource` (and fake shared store) reporting
  that state, instead of the live `StoreKitTransactionSource`.
- `KIGO_FAKE_PRICE=<string>` (and an implied fixed duration) → feed the Paywall's
  offer-display seam fixed values instead of loading a real `Product`.
- `KIGO_FAKE_PURCHASE=success|cancelled|failed` (optional) → inject a fake
  `SubscriptionPurchaser` so a UI test can exercise the tap-buy path without the
  system purchase sheet. (The purchase→activation *logic* is primarily covered by
  the headless model test in C10; this env var only exists if a UI-level buy test
  is added.)

When a variable is absent, the app falls back to the production StoreKit-backed
adapters exactly as before. The fakes and the launch wiring live in the app target
(behind `#if DEBUG`-style or always-compiled launch resolvers, consistent with how
`KIGO_FAKE_DATE` is handled) so production builds are unaffected.

Accessibility identifiers on the Paywall elements (`paywall.entry`,
`paywall.benefits`, `paywall.price`, `paywall.buy`, `paywall.restore`,
`paywall.terms`, `paywall.privacy`, `paywall.manage`) are the test's assertion
surface, matching the `kigo.*` / `microseason.*` convention already used by the
Today screen UI test (C5).

## Consequences

- C9 is verified against the **real, reachable** Paywall in the live app, headless
  and deterministic — catching the "screen exists but is never wired in" failure
  (the exact state this feature started from) the way C8 catches the widget
  mis-wiring.
- The launch-env fakes are a test-only seam; the real purchase, real product
  loading, and manage-subscription deep link remain off the gating path as J4
  (ADR 0009). The UI test proves *wiring and presentation*, not the live
  transaction.
- New StoreKit-dependent UI states inherit the convention: add a `KIGO_FAKE_*`
  variable and a launch resolver rather than reaching for a real StoreKit call in
  a UI test.
- Legal links: Terms/Privacy are configured `https` URL constants (placeholders for
  now, fenced out of scope for real legal copy). Their well-formedness is asserted
  by a headless unit test on the constants; the UI test only asserts the link
  elements are present. Real URLs must be swapped in before App Store submission.
