# KigoCore migration plan — host-side `swift test` for domain logic

Status: draft, 2026-07-04. Motivated by the simulator-toolchain audit (see
`docs/simulator-toolchain-handoff.md` and the 2026-07-03/04 halts): every unit
test currently pays the iOS-simulator tax — boot time, CoreSimulatorService
fragility (SimError 410 wedges), leaked runtime daemons, and 1.5–3 GB of
booted-sim RAM on a 16 GB host that was running ~10 GB into swap. Roughly half
the app's source files and ~half its unit-test files import only
Foundation/Observation and need none of that.

**Goal:** a local SPM package `KigoCore` holding the domain logic, tested with
`swift test` on the Mac host (seconds, no simulator, no CoreSimulator daemons),
leaving the simulator lane only for what genuinely needs it (SwiftUI/UIKit
units, KigoUITests, KigoWidgetTests, screenshot evidence).

## Two-lane test model (end state)

```bash
# Fast lane — most TDD iterations; no simulator anywhere in the stack:
scripts/xctimeout 300 swift test --package-path KigoCore

# Sim lane — UI/widget/screenshot work; unchanged hardened command from CLAUDE.md
# (boot pinned UDID + xcodebuild test -destination id=$UDID …)
```

Success signal for the fast lane: `swift test` exit 0 (its final line is a
standard `Executed N tests` summary). Both lanes run in CI order:
fast lane first (cheap failure), sim lane only when the slice touches UI.

## Package boundary

### Moves to `KigoCore/Sources/KigoCore` (phase 1 — imports are already clean)

Content domain:
- `ContentSource.swift` — already bundle-injectable; default bundle param moves
  to an explicit `Bundle` argument at the app call site (see Risks)
- `ContentStore.swift` (Foundation + Observation)
- `Manifest.swift`, `RemoteManifestSource.swift`
- `TodayResolution.swift`, `AlmanacResolution.swift`, `DayKey.swift`
- `DateProvider.swift`, `LaunchDateProvider.swift`
- `AppScreenState.swift`

Entitlement / paywall logic (the seams, not the StoreKit adapters):
- `EntitlementSharedStore.swift`
- `LaunchEntitlementProvider.swift`, `LaunchOfferDisplay.swift`,
  `LaunchPurchaser.swift`
- `PaywallConfig.swift`
- the `EntitlementTransactionSource` protocol (currently in
  `EntitlementProvider.swift` — split the protocol out; the StoreKit adapter
  stays, see below)

i18n:
- `LocalizedTextLanguage.swift`
- `LaunchLanguageStore.swift`, `UserDefaultsLanguageStore.swift`
- `UserDefaultsAppearanceStore.swift`

Future: the `NotificationScheduler` seam from slice #220 (unmerged branch
`slice/220-notification-scheduler`) belongs in KigoCore once that branch is
reconciled — it is exactly the injectable-protocol shape this package exists for.

### Stays in the app target

- All views (`*View.swift`, `KigoApp.swift`, `BottomSheetModal.swift`),
  `KigoFont`, `KigoTheme`, `KigoPlaceholder` (SwiftUI/UIKit)
- `KigoImageSource.swift` (UIKit `UIImage`)
- `EntitlementEnvironmentKeys.swift`, `LaunchAppearanceStore.swift`,
  `LaunchColorScheme.swift` (SwiftUI)
- `EntitlementProvider.swift` / `SubscriptionPurchaser.swift` StoreKit
  adapters (thin, "correct by inspection" per ADR 0009; StoreKit 2 exists on
  macOS but the adapters' tests are the injected-fake tests, which move)
- `PaywallModel.swift` (imports WidgetKit for timeline reloads — needs a seam
  before it can move; phase 2)
- `AppInfo.swift` (reads the app's own `Bundle.main` Info.plist — semantics
  change in a package test host; not worth moving)
- `AppearancePreference.swift`, `LanguagePreference.swift` (SwiftUI imports;
  phase-2 candidates if the SwiftUI dependency turns out to be trivial)

### Test files that move (with the fixtures they use)

`ContentSourceTests`, `ContentStoreTests`, `ContentRootStateTests`,
`ContentLocalizationCompletenessTests`, `LocalizableContentTests`,
`ManifestValidationTests`, `ResolutionTests`, `AlmanacWiringTests`,
`LaunchDateProviderTests`, `LaunchEntitlementProviderTests`,
`EntitlementTests`, `PaywallConfigTests`, `PaywallTests`\*,
`LanguagePreferenceTests`\* — plus `Tests/Fixtures/*.json` become package test
resources loaded via `Bundle.module`.

\* = verify during the slice: these import only XCTest, but if the type under
test stays in the app (PaywallModel, LanguagePreference), the test stays too.

Stays in the sim lane: `SmokeTests`, all `*ScreenshotTests`, `KigoFontTests`,
`KigoImageSource*Tests`, `KigoPlaceholderTests`, `AppearancePreferenceTests`,
`LaunchColorSchemeTests`, `LocalizationTests` (SwiftUI/UIKit),
`AlmanacContentValidationTests`/`AlmanacResolutionTests` (SwiftUI import —
check whether it's vestigial; if so they move too), and the whole of
KigoUITests / KigoWidgetTests / KigoStoreKitIntegrationTests.

Net: **~12–14 of 28 unit-test files (~120+ of 213 tests) leave the simulator
in phase 1**, and those are the suites the TDD inner loop reruns most.

## Mechanics

1. **Package layout** (repo root):
   ```
   KigoCore/
     Package.swift          # swift-tools-version 6.0, platforms: [.iOS("26.0"), .macOS("26.0")]
     Sources/KigoCore/…
     Tests/KigoCoreTests/…  # @testable import KigoCore still works host-side
       Fixtures/…           # resources: [.copy("Fixtures")] → Bundle.module
   ```
2. **XcodeGen wiring** in `project.yml`:
   ```yaml
   packages:
     KigoCore: { path: KigoCore }
   targets:
     Kigo:
       dependencies: [ { package: KigoCore } ]
     KigoWidgetExtension:
       dependencies: [ { package: KigoCore } ]   # replaces file-sharing of moved sources
   ```
3. **API surface:** moved types gain `public` where the app/widget use them
   (package-internal + `@testable` covers the tests). Keep `public` minimal —
   the compiler errors after the move are the checklist.
4. **Concurrency:** the package inherits Swift 6 strict concurrency
   (`swiftLanguageMode: .v6` in Package.swift) — same guarantees as today.
5. **CLAUDE.md** gains the two-lane section; the afk skills' "run the suite"
   step becomes: fast lane always, sim lane when the slice's criteria mention
   UI/screenshot evidence.
6. **CI (optional follow-up):** `afk-ci` runs the fast lane as a first step —
   it's cheap even on the 10× macOS runner; a later optimization can move it
   to a 1× Linux runner if KigoCore stays Foundation-pure.

## Risks / traps for the implementer

- **`ContentSource`'s `Bundle.main` fallback**: in a package, `Bundle.main` is
  the test *runner*, not the app. The initializer must take the bundle
  explicitly (app passes `.main`; package tests pass `.module`). The current
  code already anticipates this (comment at `ContentSource.swift:37-44`).
- **App Group `UserDefaults`** (`EntitlementSharedStore`): `swift test` on the
  host has no app-group entitlement — `UserDefaults(suiteName:)` still returns
  a store, but not a shared container. Tests must inject a suite name / plain
  `UserDefaults` (verify they already do; if not, that's the first red test).
- **Widget target file-sharing**: any moved file currently compiled into both
  `Kigo` and `KigoWidgetExtension` must come out of both `sources:` lists —
  XcodeGen will not error on a dangling shared path, so grep `project.yml`.
- **Localization resources**: `LocalizableContentTests` /
  `ContentLocalizationCompletenessTests` read content catalogs — their
  fixtures must travel into the package or the tests keep a path-relative
  escape hatch (prefer `Bundle.module`).
- **Do not migrate UI-adjacent files "while you're here"** — phase 2 exists so
  phase 1 slices stay reviewable and the sim suite shrinks monotonically.

## Slice breakdown (afk-loop shaped, tracer-bullet order)

1. **Walking skeleton:** create `KigoCore` with exactly `DayKey` +
   `DayKeyTests` (if none exist, move `ResolutionTests`' DayKey cases), wire
   XcodeGen `packages:`, app imports KigoCore, **both lanes green** end to end.
   This slice proves the whole pipeline; everything after is bulk transfer.
2. **Content domain:** move the content-domain files + their 6 test files +
   JSON fixtures (`Bundle.module`). Sim suite loses those tests; fast lane
   gains them; app behavior unchanged (screenshot of Today view as evidence).
3. **Entitlement/paywall logic:** protocol split
   (`EntitlementTransactionSource` out of the StoreKit adapter), move launch
   stores + configs + their tests.
4. **i18n:** move language/appearance stores, `LocalizedTextLanguage`, their
   tests; verify `ContentLocalizationCompletenessTests` fixtures resolve via
   `Bundle.module`.
5. **Two-lane wiring:** CLAUDE.md + afk skills updated; sim-lane suite list
   is now explicitly "UI-bound only"; wrapper optionally skips
   `ensure_sim_ready` pre-boot when the active slice is fast-lane-only.
6. *(Phase 2, separate PRD if wanted):* `PaywallModel` WidgetKit seam,
   `LanguagePreference`/`AppearancePreference` SwiftUI split, Linux CI lane.

Each slice's evidence procedure: fast lane green (`swift test` exit 0 with the
migrated count), sim lane green (`** TEST SUCCEEDED **`), and the migrated
tests *absent* from the sim run's suite list (proves they actually moved).
