# ADR 0009 — StoreKit behind injected seams; real purchase off the gating path

**Status:** Accepted
**Date:** 2026-06-15
**Criteria:** C6 (entitlement/restore logic), C10 (purchase logic); referenced by C7/C8 and the StoreKit constraint in GOAL.md / CLAUDE.md

> This ADR documents a decision that has governed the codebase since the C6 work
> but whose record was previously a dangling reference (every "see ADR 0009"
> pointed at a file that did not exist). It is written down here, unchanged in
> substance, and extended to cover the purchase action added for the in-app
> Paywall (C9/C10).

## Context

The app sells one auto-renewable subscription (widget access) through StoreKit 2.
The autonomous afk- loop verifies every hard criterion by executing it headlessly
under `xcodebuild test` from the CLI, unattended, with a hard per-iteration time
budget.

Driving **real** StoreKit from that path does not work and actively wedges the loop:

- `SKTestSession.buyProduct(...)` under `xcodebuild test` from the CLI either throws
  `SKInternalErrorDomain Code=3` or silently falls through to the production App
  Store and **hangs indefinitely** — on recent simulator runtimes (notably iOS
  26.5) the CLI does not push the `.storekit` configuration to the simulator's
  `storekitd`. It only works through Xcode's IDE launch path (Cmd+U), which the
  public CLI cannot invoke.
- The same hazard applies to anything that touches the live App Store: a real
  `Product.purchase()` (presents the system purchase sheet — needs a human),
  `Product.products(for:)` (loads offer metadata from App Store Connect), and
  `AppStore.showManageSubscriptions` (needs a live scene + account).

A criterion that can only be satisfied by such a seam is the single most reliable
way to hang an unattended run. This trap already burned three 45-min iterations on
the C6 entitlement slice before the seam split below was adopted.

## Decision

**Drive all StoreKit through narrow, injectable protocols; verify the *logic*
against in-memory fakes headlessly; keep every *real* StoreKit action off the
gating path.** Concretely:

- **Reading entitlements:** `EntitlementTransactionSource.activeProductIDs()`.
  Production = a thin adapter over `Transaction.currentEntitlements`, correct by
  inspection. Tests inject a fake. (`EntitlementProvider`, C6.)
- **Starting a purchase:** `SubscriptionPurchaser` (added for C10). Production =
  a thin adapter over `Product.purchase()`. Tests inject a fake returning a
  configured outcome (success / cancelled / failed) and, on success, flip the fake
  transaction source to report the product as owned — so the purchase→refresh→
  activation *logic* is exercised with no purchase sheet.
- **Offer metadata (price/duration):** an injectable "offer display" / ProductInfo
  seam. Production = a StoreKit `Product`. Tests inject fixed values so the
  Paywall's price/duration *rendering* is deterministic. (C9.)
- **The shared entitlement store** (`EntitlementSharedStore`) is likewise injected
  (ADR 0011).

Every real adapter is deliberately a thin pass-through, correct by inspection. The
real, human-or-network-bound actions — the purchase sheet, real product loading,
`SKTestSession` end-to-end, manage-subscription deep link — are verified only as
**judgment claims** (J3, J4) in the Xcode IDE / on a signed build, **never as a
`C*` evidence step**.

## Consequences

- Entitlement, restore, and purchase **logic** run green headlessly in
  milliseconds, deterministically, with no `storekitd`, no simulator purchase, no
  network, no provisioning.
- The on-path residual real-wiring checks (the production adapters exist and are
  thin; the Paywall is actually constructed and reachable in the live app, C9; the
  widget shares the entitlement, C8) catch the "logic green, product mis-wired"
  failure without driving the flaky seam.
- The cost is that the genuinely end-to-end purchase is **not** loop-certified — it
  is a J* the human reviews. This is accepted: it is an Apple platform defect, not
  something an implementer can code around, and the alternative (gating on it) is a
  guaranteed hang.
- Any future StoreKit touchpoint inherits this rule: wrap it behind a protocol,
  fake it in tests, and fence the real call off the gating path.
