# ADR 0023 — GOAL.md evidence procedures follow tests to their KigoCore location

**Status:** Accepted
**Date:** 2026-07-04
**Criteria:** C6, C9, C12, C15 (documentation only — no behavior change)
**Relates to:** `docs/kigocore-migration-plan.md`, commit c92f183 (KigoCore host-side
swift-test lane for domain logic)

## Context

Commit c92f183 moved `EntitlementTests`, `PaywallConfigTests`,
`LocalizableContentTests`, and `LanguagePreferenceTests` — along with the domain
sources they exercise — from `Tests/KigoTests/` (the simulator-lane `KigoTests`
bundle) to `KigoCore/Tests/KigoCoreTests/` (the host-side SPM package introduced by
`docs/kigocore-migration-plan.md`). The four suites test pure domain logic (the
entitlement engine, the paywall config constants, the localized-content schema, and
the language-preference seam) with no SwiftUI/UIKit/StoreKit dependency, so they run
in milliseconds via `swift test --package-path KigoCore`, with no simulator anywhere
in the stack.

`docs/GOAL.md`'s evidence procedures for C6, C9, C12, and C15 were not updated in
that commit: they still read `-only-testing:KigoTests/EntitlementTests` (and the
equivalent for the other three suites) — the canonical sim-lane `xcodebuild test`
invocation. That invocation no longer finds these suites (they are not part of the
`KigoTests` bundle any more), so run verbatim it would report `Executed 0 tests` and
pass vacuously — exactly the false-pass mode GOAL.md's own nonzero-count guard exists
to catch, except here the suite is real and passing, just addressed at the wrong test
target.

## Decision

Update the four affected evidence-procedure commands in `docs/GOAL.md` to the
fast-lane form:

```
swift test --package-path KigoCore --filter <Suite>
```

replacing the stale `-only-testing:KigoTests/<Suite>` sim-lane form, for:

- C6 → `EntitlementTests` (7/7 passing)
- C9 → `PaywallConfigTests` (2/2 passing)
- C12 → `LocalizableContentTests` (10/10 passing)
- C15 → `LanguagePreferenceTests` (21/21 passing)

Each was re-run against this ADR's commit to confirm the new invocation passes with
the counts above before landing. This is a documentation-lag fix only: the suites,
their assertions, and the criteria they gate are unchanged — only the command an
evidence procedure runs to reach them moves, mirroring where the tests themselves
already moved.

## Why not …

- **Leave the stale `-only-testing:KigoTests/<Suite>` commands as-is.** They read as
  a false "unmet" (or worse, a silent vacuous pass if the nonzero-count guard is
  applied loosely) for four criteria that are, in fact, fully satisfied — an avoidable
  audit trap for no benefit.
- **Fix every stale `-only-testing:KigoTests/...` reference in GOAL.md in one pass.**
  Several other criteria (C1–C4) reference suites that also moved in c92f183, but
  fixing them is out of scope for this slice (#228, PRD #227) — this ADR and its
  commit touch only the four references the slice explicitly called out. The broader
  cleanup is tracked as follow-up, not bundled here.

## Consequences

- C6/C9/C12/C15's evidence procedures now name the actual lane and location their
  suites run in, so a future audit's re-run of the documented command finds the
  suite and reproduces the pass to be a real, on-target check rather than a vacuous
  no-op.
- The remaining `-only-testing:KigoTests/...` references for suites not yet migrated
  (or migrated but not yet documented) are unaffected by this ADR and remain a known,
  separate documentation-lag item.
