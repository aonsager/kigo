# Goal: Kigo — a daily seasonal-word wellness app

<!-- afk:human-write-only — the loop reads this file and never edits it.
     Met/unmet is derived by executing evidence procedures; no status is stored here. -->

## North star

Kigo is a calm iOS app that gives a person one quiet moment a day. On opening it,
they see a single traditional Japanese seasonal word — the **Kigo** for today —
presented over a large, evocative full-bleed image, with a brief note on the word's
meaning and significance, and a small reading of the current Japanese **Microseason**
(the Kō, with its parent Sekki beneath). That is the whole of the main experience:
no calendar, no feed, no streaks. It should feel like a tasteful object on the
nightstand, closer to a wellness app than a productivity tool.

The same Kigo is shown to everyone on a given date — the content is decided in
advance by a **Daily Map** and the Kigo always matches the current season. The Daily
Map is now keyed by **absolute date**, populated as an instrumented dummy dataset for
**every day of 2026** (`2026-MM-DD` → Kigo), each description stamped with its own date
so the right record is verifiably being read (ADR 0016, reversing the earlier perennial
`MM-DD` keying); the 72 Kō / 24 Sekki stay perennial. Content is loaded through a
`ContentSource` seam, served as a **fully localized** Japanese/English **Manifest** that
can be **updated from a versioned remote URL** on app open (ADR 0017) — for now it is
also generated into the repo and bundled as the seed/fallback.

The app is free. A single auto-renewable subscription ("widget access") lets a
subscriber put a small version of today's image+Kigo on their home screen as a
**Widget**. Non-subscribers who add the widget still see the day's Kigo name — just
not the image, which is the part the subscription reveals.

That subscription is bought **in-app**: a small, unobtrusive **Upgrade entry** in a
corner of the Today screen opens a **Paywall** sheet. For a **Basic** (free) user
the Paywall presents the one premium benefit — revealing the image on the home-screen
Widget — with a prominent buy button, a Restore Purchases button, the price and
subscription duration, and the App-Store-required Terms of Use and Privacy Policy
links. Buying it (or restoring) activates the **Entitlement** and unlocks the Widget
image; a **Premium** user opening the Paywall sees an active/manage state instead.
The entry stays unobtrusive on purpose — the prominence lives inside the splash, not
on the calm Today screen (J1).

Audience: people who want a small daily encounter with the Japanese seasons —
contemplative, aesthetic, low-friction.

### Visual revamp (Asagiri) — added 2026-06-16

The app's deliberately-minimal first design is being replaced by a full visual revamp,
internally **Asagiri** (朝霧): full-bleed per-day photography, centered sumi-ink **Mincho**
typography, generous quiet space, a feathered frosted-glass plate that keeps the text
legible over busy photos, and a gentle entrance — in **both light and dark** appearance,
following the system. The canonical reference is the `Kigo Revamp.dc.html` handoff
(design tokens, layout, motion, and the per-surface accessibility identifiers it preserves).

The revamp keeps everything above and **deliberately reuses the existing accessibility
identifiers** (`kigo.*`, `paywall.*`, `microseason.ko/sekki`, the placeholders), so the
prior capabilities (C1–C10) still hold after the reskin. It adds three **opt-in overlays on
the Today screen** and one settings change — none of which add a second destination or
violate the "only today" calm:

- **Microseason Almanac** — the floating Microseason line becomes a resting **Year timeline**
  (sekki · kō above 72 ticks) that taps to expand a sheet with the kō/sekki year-positions,
  day-within-kō and kō-within-sekki **progress gauges**, glosses, and prose.
- **Image Attribution panel** — an **(i)** control (top-left) slides a per-image credit panel
  down from the top.
- **Settings menu** — the bare **Upgrade entry** becomes a top-right **Settings gear** opening
  a sheet with three sections: a **Language preference** switcher (JP/EN), the widget
  subscribe offer (the Paywall, unchanged in substance), and the legal links.

Pixel-fidelity to the Asagiri mockup is inherently subjective and is reported as a judgment
claim (J6), **never a termination gate** — what the loop hard-gates is the new *structure,
data, wiring, and measurable composition*, and that both appearances render without breaking.

## Out of scope

The autonomous planner must treat these as a hard fence — never plan work that
serves only these, even if it seems helpful:

- **Browsing other days.** Today only. No calendar, no history, no swiping to past
  or future Kigo, no archive. This is the core wellness-vs-calendar distinction.
- **User accounts & sync.** No sign-in, profiles, or cloud sync. Content is identical
  for all users and needs no identity.
- **Notifications.** No daily push or local reminders in this goal.
- **Sharing & onboarding.** No share sheet / social export, no multi-screen
  onboarding or tutorial. The Paywall sheet is the only new screen — it is not an
  onboarding flow and is never shown unprompted (only when the user taps the Upgrade
  entry).
- **Subscription product complexity.** Exactly one product
  (`…widgets.monthly`). No introductory pricing, free trials, promotional/win-back
  offers, no annual plan, and no second tier. The Paywall presents one straight
  monthly subscription.
- **Invented premium benefits.** Premium unlocks exactly one capability — the Widget
  Gate revealing the image. The Paywall must present that honestly; do not advertise
  features the app does not deliver (e.g. extra content, themes). Expanding what
  Premium unlocks is a separate goal amendment, not loop work.
- **In-app subscription management.** No custom manage/cancel/upgrade UI. For a
  Premium user the "manage" affordance is at most a deep link to Apple's
  system-managed subscription screen (the real deep link is off the gating path —
  J4); the loop builds no billing-management UI of its own.
- **Real legal copy & hosting.** Terms of Use and Privacy Policy are placeholder
  `https` URL constants for now (their presence and well-formedness are gated;
  authoring and hosting the real documents are out of scope — see C9 / ADR 0013).
- **A content backend / server.** No server, API, or CMS is built or deployed. The app
  *consumes* a versioned manifest from a placeholder remote `https` URL (the client side —
  C21/ADR 0017), but **authoring and hosting** that endpoint is out of scope; content is
  generated into the repo behind the `ContentSource` seam and bundled as the seed/fallback.
- **Sourcing real photography/art.** Images are tasteful placeholders for now
  (see ADR 0001 / J2); curating real imagery is not part of this goal.
- **Pre-iOS-26 support.** Deployment target is iOS 26 (see ADR 0002).
- **Region/number/date locale formatting.** Full JP⇄EN **content** localization is now
  **in scope** — English prose for every Kigo/Kō/Sekki description and gloss, English
  attribution, and **romanized (romaji) readings** in English mode, switching **live** (C19/C20,
  ADR 0018) on top of the C15 chrome strings. What stays out of scope is **locale-aware
  number/date/currency formatting** (no region localization). **Kanji content names never
  translate** — they show identically in both languages.
- **Browsing the year via the Almanac.** The Microseason Almanac shows only *today's*
  position in the year (counters + gauges + this kō/sekki's copy). It must never become a
  way to scrub to other days, kō, or sekki — that would breach the Today-only fence above.
- **Real photography & real attribution values.** Images remain tasteful placeholders (as
  before); the new **Image Attribution** strings are likewise placeholders. Their schema
  presence/well-formedness is gated (C12/C14); sourcing real images and real credits is out
  of scope (J2/J6).
- **In-app subscription management UI (restated).** Folding the subscribe offer into the
  **Settings menu** does not add manage/cancel UI; it is still one product, one honest
  benefit, with at most a deep link to Apple's system screen (J4).

## Constraints

Standing rules every milestone inherits:

- **Stack:** SwiftUI app + WidgetKit extension + StoreKit 2. Swift 6 / Xcode 26.4.
- **Project tooling:** multi-target Xcode project generated by XcodeGen from a
  committed `project.yml`. The canonical commands the whole loop uses:
  - `xcodegen generate`
  - The canonical test invocation — used **verbatim** by every test-based procedure
    below (substitute the suite). It pins the simulator runtime and fails fast so a
    hung test cannot wedge the loop (rationale in CLAUDE.md "Build & test"):
    ```
    perl -e 'alarm shift; exec @ARGV' 720 \
      xcodebuild test -scheme Kigo \
        -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
        -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
        -maximum-test-execution-time-allowance 300 \
        CODE_SIGNING_ALLOWED=NO -only-testing:<suite>
    ```
  - On success `xcodebuild` prints `** TEST SUCCEEDED **` (exit 0); that string is the
    pass observable for every test-based procedure below. **`** TEST SUCCEEDED **`
    alone is not sufficient** — `xcodebuild` prints it with `Executed 0 tests` and
    exit 0 when an `-only-testing` suite does not exist (verified: a nonexistent
    suite passes vacuously). So every test-based procedure below also asserts a
    **nonzero executed-test count** — the run output must match
    `Executed [1-9][0-9]* test` (e.g. pipe through
    `grep -Eq 'Executed [1-9][0-9]* test'`). This is what makes "the suite isn't
    written yet" read as **unmet**, not as a vacuous pass, for every criterion that
    introduces a new suite.
- **Deployment target:** iOS 26; all evidence runs on an iOS 26 iPhone 17 simulator
  (ADR 0002). No `#available` gating for pre-26 APIs.
- **Content seam:** all content is read through a `ContentSource`; tests use
  `BundledContentSource` over generated, committed files. No live network in any
  evidence procedure (ADR 0001).
- **Testability seams:** the current date is injected through a `DateProvider`
  (overridable in tests and via the `KIGO_FAKE_DATE=YYYY-MM-DD` launch environment
  variable); the StoreKit entitlement, the purchase action
  (`SubscriptionPurchaser`), the offer-display (price/duration) source, and the
  app↔widget shared store are all injectable so logic is verifiable in-process
  without real provisioning. The Paywall's StoreKit-dependent UI states are driven
  in `KigoUITests` through launch-environment fakes mirroring `KIGO_FAKE_DATE` —
  `KIGO_FAKE_ENTITLEMENT=active|inactive` and `KIGO_FAKE_PRICE=<string>` (and
  optional `KIGO_FAKE_PURCHASE=…`); when absent the app uses the production
  StoreKit-backed adapters (ADR 0013).
- **StoreKit testing (ADR 0009):** entitlement, restore, and purchase *logic* are
  verified headlessly through **injectable seams** — the transaction source
  (`activeProductIDs()`), the `SubscriptionPurchaser` (`purchase(_:)`), and the
  offer-display source — filled by in-memory fakes in tests, with no `storekitd`, no
  simulator purchase, no App Store Connect. Each production adapter (reading
  `Transaction.currentEntitlements`, calling `Product.purchase()`, reading a real
  `Product`) is a thin pass-through, correct by inspection. Driving a *real* purchase
  through `SKTestSession` / `Product.purchase()` under `xcodebuild test`, loading a
  real `Product`, and the manage-subscription deep link are all **off the gating
  path** (they hang or need a human/account from the CLI — CLAUDE.md / ADR 0009);
  any such integration test is non-blocking, runs only in the Xcode IDE or a manual
  lane, and is reported as J4 — never as a `C*` evidence step.
- **Identifiers:** bundle id `com.tomeitotameigo.kigo`, app group
  `group.com.tomeitotameigo.kigo`, subscription product
  `com.tomeitotameigo.kigo.widgets.monthly` (loop may refine the app group / product
  naming, but the bundle id is fixed).
- **Date semantics:** "today" is the device's local calendar day (CONTEXT.md).
- **Revamp launch-env injection (extends ADR 0013):** the `KIGO_FAKE_*` convention gains two
  variables so the revamp's appearance- and language-dependent UI is driven deterministically
  under headless UI test — `KIGO_FAKE_APPEARANCE=light|dark` (pins
  `.preferredColorScheme`; absent ⇒ follow system) and `KIGO_FAKE_LANGUAGE=ja|en` (pins the
  Language preference; absent ⇒ the persisted value, default Japanese). Same pattern as the
  existing `LaunchDateProvider`/`LaunchEntitlementProvider`/`LaunchOfferDisplay` resolvers.
- **Fonts:** the Asagiri type identity uses **Shippori Mincho** and **Zen Kaku Gothic New**
  (both OFL, free to bundle). They are bundled into the app and registered in `UIAppFonts`;
  C17 gates that wiring against the built product (a missing/unregistered font silently
  falls back to the system font — exactly the kind of regression C8 was written to catch).
- **Content schema (ADR 0014):** the Contract is extended once to be localization-ready
  (Kō `description`; Sekki `gloss`+`description`; per-image `attribution`; optional English
  fields decodable whether present or absent; `schemaVersion` bumped). C12 gates the
  Japanese-side completeness and the optional-English forward-compatibility.
- **Almanac indexing:** all year-positions are **1-indexed** (梅子黄 = 27/72), matching the
  lit timeline tick (CONTEXT.md; overrides the mockup's literal "26/72").
- **Daily Map keying (ADR 0016):** the Daily Map is keyed by **absolute `YYYY-MM-DD`**,
  populated for **every day of 2026** (365 entries; no `02-29`); resolution looks up today's
  absolute date and an out-of-range date yields the defined "content unavailable" state (C3).
  The 72 Kō / 24 Sekki keep **perennial `MM-DD`** date ranges (the Almanac resolver C11 is
  unchanged). Each Daily-Map description carries its own ISO date (`2026-MM-DD`) for verification.
- **Content schema migration (ADR 0018, supersedes part of ADR 0014):** `DailyMapEntry.description`,
  `DailyMapEntry.reading`, `Ko.reading`, and `Sekki.reading` are `LocalizedText` (`ja`+`en`;
  readings: `ja`=hiragana, `en`=romaji); all `LocalizedText` fields are populated in both
  languages; `kanji` stays a single untranslated `String`; `schemaVersion` is bumped. The decode
  must still succeed with or without `en` (ADR 0014 forward-compat preserved).
- **Content version + remote update (ADR 0017):** the Manifest carries a monotonic integer
  **`version`** (distinct from `schemaVersion`). A **`RemoteManifestSource`** seam
  (`fetchLatest() async throws -> Manifest`) is injectable; the production adapter is a thin
  `URLSession` reader of a placeholder `https` URL constant. On app open the store serves local
  content immediately and checks the remote in the background; it replaces the local cache **iff**
  the remote `version` is strictly newer **and** the body decodes/validates, and degrades silently
  to the local copy on any failure. **No live network in any evidence procedure** (ADR 0001): the
  update logic is gated through the injected fake (C21); the real fetch is off the gating path (J7).
- **Live language store:** the persisted Language preference is exposed as a single observable
  store the Today screen, Almanac, Attribution panel, and chrome all read; changing it re-renders
  every visible string **without relaunch** (C20). `KIGO_FAKE_LANGUAGE=ja|en` still pins only the
  *initial* value (ADR 0013); the live toggle is exercised through the Settings switcher.

## Criteria

Goal state met ⇔ every `C*` procedure below passes on `main`.

### C1: Project builds and its test suite runs (walking skeleton)

- **Depends on:** none
- **Statement:** The multi-target project (app + widget extension + test target)
  generates and builds, and a real test suite executes green on the iPhone 17
  simulator. This pins the toolchain every other criterion relies on.
- **Evidence:**
  1. Run `xcodegen generate` — expect exit 0 and a generated `Kigo.xcodeproj`.
  2. Run `xcodebuild build -scheme KigoWidgetExtension -destination 'platform=iOS Simulator,name=iPhone 17'`
     — expect `** BUILD SUCCEEDED **` and exit 0 (proves the widget extension target compiles).
  3. Run the canonical test invocation (Constraints) with `-only-testing:KigoTests/SmokeTests`
     — expect `** TEST SUCCEEDED **` and exit 0, with `SmokeTests` containing ≥1 test.

### C2: Content dataset is a complete, versioned 2026 dataset (amended — ADR 0016/0018)

- **Depends on:** C1
- **Statement:** A committed Manifest conforms to the Contract: a full **absolute-date 2026
  Daily Map**, the canonical 72 perennial Kō, and the 24 Sekki, each entry well-formed, carrying
  a monotonic content `version`. (Literary quality is not gated here — see J2.)
- **Evidence:**
  1. **Data-shape precheck (external, deterministic).** Run against the bundled `Resources/manifest.json`:
     ```
     python3 - <<'PY'
     import json, re, datetime, sys
     m = json.load(open('Resources/manifest.json'))
     dm = m['dailyMap']
     assert isinstance(m.get('version'), int), 'missing integer content version'
     assert 'schemaVersion' in m, 'missing schemaVersion'
     ks = sorted(dm)
     assert len(ks) == 365 and all(re.fullmatch(r'2026-\d{2}-\d{2}', k) for k in ks), 'keys must be 365 2026-MM-DD'
     d = datetime.date(2026,1,1); want=[]
     while d.year == 2026: want.append(d.isoformat()); d += datetime.timedelta(days=1)
     assert ks == want, 'must cover every 2026 day, no gaps'
     for k, e in dm.items():
         assert e['kanji'] and e['imageId'], k
         for f in ('reading','description'):
             assert isinstance(e[f], dict) and e[f].get('ja'), f'{k}.{f} must be localized with ja'
         assert len(e['description']['ja']) >= 20, k
     print('OK'); sys.exit(0)
     PY
     ```
     — expect `OK` and exit 0. *(Fails today: keys are `MM-DD`, no `version`, readings/description
     are plain strings — so this reads unmet until the dataset is migrated.)*
  2. Run the canonical test invocation (Constraints) with `-only-testing:KigoTests/ManifestValidationTests`
     — expect `** TEST SUCCEEDED **`, exit 0, and `Executed [1-9][0-9]* test`. The suite loads the
     bundled Manifest **through the decoder** and asserts:
     - all 365 `2026-MM-DD` keys present and covering every day of 2026; each entry has non-empty
       `kanji`, a `reading` and a `description` (each `LocalizedText` with non-empty `ja`,
       `description.ja` ≥ 20 chars), and an `imageId`;
     - exactly 72 Kō, each with non-empty `kanji`/`reading.ja`/`gloss` and a `sekkiId` that resolves
       to one of exactly 24 Sekki; the 72 Kō **perennial `MM-DD`** date ranges are contiguous and
       cover the whole year with no gaps or overlaps;
     - `schemaVersion` and an integer `version` are present.

### C3: Content loads through ContentSource and survives offline

- **Depends on:** C1, C2
- **Statement:** The app reads content through `ContentSource`; once content is
  cached, today's content is served with no network, and a cold start with neither
  cache nor source yields a defined loading state rather than an error to the UI.
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with `-only-testing:KigoTests/ContentSourceTests`
     — expect `** TEST SUCCEEDED **` and exit 0. The suite asserts:
     - `BundledContentSource` returns a Manifest equal to the committed fixture;
     - after a successful load the cache returns today's entry when the source is
       then replaced with one that always fails (offline simulation);
     - with an empty cache and a failing source, the content store resolves to a
       `.loading`/`.unavailable` state (no thrown error surfaces to the UI layer).

### C4: Today resolves to the correct Kigo and Microseason (amended — ADR 0016)

- **Depends on:** C1, C2
- **Statement:** Given a date, the app resolves the correct Kigo by **absolute 2026 date** (via
  the Daily Map) and the correct current Kō and parent Sekki by **perennial `MM-DD`** range; a
  date outside the dataset resolves to the defined unavailable state, not a crash or wrong day.
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with `-only-testing:KigoTests/ResolutionTests`
     — expect `** TEST SUCCEEDED **`, exit 0, and `Executed [1-9][0-9]* test`. The suite injects a
     `DateProvider` and asserts, for a fixed set of 2026 dates spanning all four seasons (including
     a Kō boundary day):
     - the resolved Kigo equals the Daily Map entry for that **`2026-MM-DD`** key, **and** the
       resolved entry's `description.ja` and `description.en` each contain that ISO date string
       (the date-stamp instrumentation — proves the correct per-day record is read);
     - the resolved Kō is the one whose **perennial `MM-DD`** range contains the date, and its
       `sekkiId` resolves to the expected Sekki;
     - a **leap day** (e.g. `2024-02-29`, injected) resolves to a defined Kō without crashing
       (Kō ranges are perennial, so a `02-29` still falls inside a range);
     - an **out-of-range** date (e.g. `2027-01-01`, with no Daily-Map entry) resolves to the
       defined "content unavailable" state (no entry, no thrown error to the UI).

### C5: Today screen shows today's Kigo and Microseason

- **Depends on:** C1, C2, C3, C4
- **Statement:** The main screen renders today's full-bleed image, the Kigo kanji,
  reading and description, and the small Microseason display (Kō primary, Sekki
  secondary), for the resolved date.
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with `-only-testing:KigoUITests/TodayScreenUITests`
     — expect `** TEST SUCCEEDED **` and exit 0. The UI test launches the app with
     environment `KIGO_FAKE_DATE=2026-06-12` and asserts, via accessibility
     identifiers, that the today screen shows: an image element
     (`id "kigo.image"`), the Kigo kanji static text matching the Manifest's `06-12`
     entry (`id "kigo.kanji"`), a non-empty description (`id "kigo.description"`),
     and the Kō name (`id "microseason.ko"`) with the Sekki (`id "microseason.sekki"`).

### C6: Subscription paywall grants and restores widget-access entitlement

- **Depends on:** C1
- **Statement:** A paywall offers one auto-renewable "widget access" subscription;
  purchasing it makes the Entitlement active, the active state persists and is
  readable for the widget, and restore re-establishes it; with no purchase the
  Entitlement is inactive.
- **Evidence:**
  1. Run the canonical test invocation (see Constraints) with
     `-only-testing:KigoTests/EntitlementTests` — expect `** TEST SUCCEEDED **` and
     exit 0. The suite drives the entitlement engine through its **injected
     transaction source** (the StoreKit seam) and **injected shared store** — no
     `SKTestSession`, no simulator purchase, so it runs headless in seconds. It
     asserts:
     - when the transaction source reports no entitlements, the provider reports
       inactive;
     - when the source reports the `com.tomeitotameigo.kigo.widgets.monthly` product
       as entitled, the provider reports active and writes the active flag to the
       injected shared store;
     - after the shared store's in-memory state is cleared and the source is
       re-synced (restore), the provider reports active again.
  2. The production transaction source (reading StoreKit 2's
     `Transaction.currentEntitlements`) is a thin adapter verified by inspection; a
     real-purchase `SKTestSession` integration test, if present, is **non-blocking**
     and excluded from this suite (it hangs under `xcodebuild` CLI — CLAUDE.md / ADR
     0009), so it never gates this criterion.

### C7: Widget renders today's content, gated by entitlement

- **Depends on:** C1, C2, C3, C6
- **Statement:** The widget (systemSmall and systemMedium) builds a timeline whose
  current entry is today's Kigo, advancing to the next day at local midnight. When
  the Entitlement is active the entry reveals the image; when inactive it shows the
  Kigo name (kanji + reading) without the image.
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with `-only-testing:KigoWidgetTests/WidgetTimelineTests`
     — expect `** TEST SUCCEEDED **` and exit 0. With an injected `DateProvider`,
     shared store, and `ContentSource`, the suite asserts:
     - the timeline's first entry corresponds to the injected date's Kigo, and the
       next entry's date is the following local midnight;
     - for both `systemSmall` and `systemMedium`, an entry built with an **active**
       entitlement has `showsImage == true` and carries the `imageId`;
     - an entry built with an **inactive** entitlement has `showsImage == false` and
       still carries the Kigo kanji + reading.

### C8: The widget works through the real built artifact (honest integration)

- **Depends on:** C3, C6, C7
- **Statement:** The widget's content and shared-container wiring work through the
  *real* built artifact, not injected stand-ins: the extension actually carries the
  content it loads, the real content path resolves today's Kigo, and the app↔widget
  App Group is configured. This is the gate that catches "logic green, product
  mis-wired" — the failure where every widget logic test (C7) passed yet the widget
  rendered blank on a device because `manifest.json` was never bundled into the
  extension and the App Group was never configured. C7 verifies the timeline *logic*
  against an injected manifest and shared store; C8 verifies the production *wiring*
  those injections hide.
- **Evidence:**
  1. Run `xcodegen generate`, then build with the product path pinned:
     ```
     perl -e 'alarm shift; exec @ARGV' 720 \
       xcodebuild build -scheme Kigo \
         -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
         -derivedDataPath build CODE_SIGNING_ALLOWED=NO
     ```
     — expect `** BUILD SUCCEEDED **` and exit 0. Then run
     `test -f build/Build/Products/Debug-iphonesimulator/Kigo.app/PlugIns/KigoWidgetExtension.appex/manifest.json`
     — expect exit 0. *(Built-product wiring check: the content the extension's
     `TimelineProvider` loads is actually inside the shipped `.appex`, not only the app
     bundle. XcodeGen silently ignoring a malformed resources entry is exactly how this
     regressed.)*
  2. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoWidgetTests/WidgetRealContentTests` — expect `** TEST SUCCEEDED **`
     and exit 0, with `WidgetRealContentTests` containing ≥1 test. The suite loads content
     through the **real** `BundledContentSource` (no injected or hand-built manifest) and
     asserts that, for a pinned date, the `WidgetTimelineBuilder`'s entry carries that
     date's actual `kanji` and `reading` from the bundled manifest — proving the real
     content path resolves end-to-end, so the widget renders today's Kigo rather than the
     redacted placeholder.
  3. Run `xcodegen generate`, then assert the app↔widget App Group is declared on both
     targets:
     ```
     /usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" \
       Sources/Kigo/Kigo.entitlements
     /usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" \
       Sources/KigoWidgetExtension/KigoWidgetExtension.entitlements
     ```
     — expect both print `group.com.tomeitotameigo.kigo`. *(Build-configuration wiring
     check. On-device entitlement **enforcement** needs signing/provisioning to run and
     is verified by J3, off the headless gating path — see the "requires provisioning to
     run" row in the headless-integration-traps catalog. This step deterministically
     catches the App-Group-never-configured regression headlessly: when neither target
     declares the group, app and widget silently fall back to separate `.standard`
     stores and the subscriber image never reveals.)*

### C9: Paywall is reachable from the Today screen and presents the compliant offer

- **Depends on:** C5, C6
- **Statement:** A small **Upgrade entry** on the Today screen opens the **Paywall**
  as a sheet, verified through the *real, reachable* live app (not merely that a
  `PaywallView` type exists — it already existed fully unwired). For a **Basic**
  user the Paywall shows the honest single **Benefits** copy, the price and
  subscription duration (from the injected offer-display seam), a prominent buy
  button, a Restore Purchases button, and functional Terms of Use and Privacy Policy
  links (all required by App Store review). For a **Premium** user it shows an
  active/manage state instead of the buy button. This is the gate that catches
  "paywall built but never wired into the app" — the state this feature started from.
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoUITests/PaywallUITests` — expect `** TEST SUCCEEDED **`,
     exit 0, **and** output matching `Executed [1-9][0-9]* test` (nonzero-count
     guard; `PaywallUITests` must contain ≥1 test). Launching the **real** app via
     the launch-environment fakes (ADR 0013), the suite asserts, via accessibility
     identifiers:
     - **Basic case** — launched with `KIGO_FAKE_DATE=2026-06-12`,
       `KIGO_FAKE_ENTITLEMENT=inactive`, `KIGO_FAKE_PRICE=¥300`: the Today screen
       shows `paywall.entry`; tapping it presents a sheet that shows a non-empty
       `paywall.benefits`, a `paywall.price` whose displayed text contains the
       injected `¥300`, a non-empty `paywall.duration`, and the elements
       `paywall.buy`, `paywall.restore`, `paywall.terms`, and `paywall.privacy`.
     - **Premium case** — relaunched with `KIGO_FAKE_ENTITLEMENT=active`: tapping
       `paywall.entry` presents a sheet showing `paywall.manage` and **no**
       `paywall.buy`.
  2. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoTests/PaywallConfigTests` — expect `** TEST SUCCEEDED **`,
     exit 0, and `Executed [1-9][0-9]* test`. The suite asserts the Terms of Use and
     Privacy Policy URL constants the Paywall links to are non-nil, use the `https`
     scheme, and parse as well-formed `URL`s. *(Built-config wiring check: the links
     the UI presents point at real, well-formed URLs, not empty strings. The URLs
     are placeholders for now and the real legal copy is out of scope — ADR 0013;
     real URLs must be swapped in before App Store submission, reported under J4.)*

### C10: Buy action drives entitlement activation (purchase logic)

- **Depends on:** C6
- **Statement:** Invoking the Paywall's buy action runs the `SubscriptionPurchaser`
  seam; on a successful purchase the **Entitlement** is refreshed to active and the
  reflected `isActive` state flips to `true` (so the **Widget Gate** unlocks), while
  a cancelled or failed purchase leaves the user **Basic** with no crash. The
  purchase→activation *logic* is verified through injected fakes; the real
  `Product.purchase()` sheet is off the gating path (J4 / ADR 0009).
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoTests/PaywallPurchaseFlowTests` — expect
     `** TEST SUCCEEDED **`, exit 0, **and** output matching `Executed [1-9][0-9]* test`
     (nonzero-count guard; the suite must contain ≥1 test). With an injected fake
     `SubscriptionPurchaser`, fake transaction source, and fake shared store — no
     `SKTestSession`, no purchase sheet, so it runs headless in seconds — the suite
     asserts:
     - **success:** with the purchaser configured to succeed (flipping the
       transaction source to report `com.tomeitotameigo.kigo.widgets.monthly` as
       owned), after the model's `buy()` the model reports active (`isActive == true`)
       and the shared store records the active flag;
     - **cancelled:** with the purchaser configured to report user-cancellation,
       after `buy()` the model reports inactive (`isActive == false`), the shared
       store is not active, and no error is thrown;
     - **failed:** with the purchaser configured to throw, after `buy()` the model
       reports inactive (`isActive == false`) — the failure is handled, not crashed.

### Revamp note — C9 / C10 survive the reskin

The Asagiri revamp folds the subscribe offer into the **Settings menu** but **preserves the
`paywall.*` accessibility identifiers** (`paywall.entry` now on the Settings gear,
`paywall.sheet` on the menu, and `paywall.benefits/price/duration/buy/restore/terms/privacy/manage`
inside it). C9 and C10 are therefore **unchanged** and re-verified as written against the new
menu — if the reskin drops or moves one of those identifiers, their procedures fail and the
loop catches it. Do not renumber or rewrite C9/C10.

### C11: Microseason almanac positions resolve correctly

- **Depends on:** C1, C2, C4
- **Statement:** Given a date, the resolver derives the four **Almanac positions** the
  expanded almanac renders — the Kō year-position (N of 72, **1-indexed**), the Sekki
  year-position (M of 24, 1-indexed), the **day-within-Kō** (d of the Kō date-range length,
  1-indexed), and the **Kō-within-Sekki** (k of the Kō sharing that Sekki, 1-indexed). Pure,
  deterministic, made testable by date injection (no UI).
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoTests/AlmanacResolutionTests` — expect `** TEST SUCCEEDED **`, exit
     0, **and** output matching `Executed [1-9][0-9]* test`. Injecting a `DateProvider`, the
     suite asserts for a fixed set of dates spanning the year (including a Kō-boundary day,
     a Sekki-boundary day, and `02-29`):
     - for `2026-06-16` (梅子黄, range `06-16`–`06-20`): Kō year-position `27/72`, Sekki
       (芒種) year-position `9/24`, day-within-Kō `1/5`, Kō-within-Sekki `3/3`
       (梅子黄 is the 3rd of 芒種's three Kō: 螳螂生 06-06, 腐草為螢 06-11, 梅子黄 06-16);
     - for a mid-range date (`2026-06-18`): day-within-Kō `3/5`;
     - the counts are 1-indexed and the totals are exactly 72 (Kō) and 24 (Sekki);
     - `02-29` resolves to a defined position without crashing.

### C12: Almanac & attribution content is complete and the schema is localization-ready

- **Depends on:** C2
- **Statement:** The Manifest carries the content the Almanac and Attribution panel render,
  structurally complete and localization-ready (ADR 0014): every Kō has a non-empty
  `description`; every Sekki has a non-empty `gloss` and `description`; every Daily Map
  image has well-formed `attribution` (non-empty title, credit, license); and the schema
  decodes optional English fields whether present or absent, so English content can be added
  later without a schema break. Literary/photo quality is **not** gated here (J2/J6).
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoTests/AlmanacContentValidationTests` — expect `** TEST SUCCEEDED **`,
     exit 0, and `Executed [1-9][0-9]* test`. The suite loads the bundled Manifest and asserts:
     - all **72** Kō have a non-empty `description`;
     - all **24** Sekki have a non-empty `gloss` **and** a non-empty `description`;
     - all **366** Daily Map entries resolve to an `attribution` with non-empty `title`,
       `credit`, and `license`.
  2. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoTests/LocalizableContentTests` — expect `** TEST SUCCEEDED **`, exit
     0, and `Executed [1-9][0-9]* test`. The suite asserts the Manifest decodes a fixture
     entry that **includes** the optional English field(s) and one that **omits** them (both
     succeed and round-trip), pinning the forward-compatibility ADR 0014 requires.

### C13: Today shows the resting timeline and expands the almanac (reachable)

- **Depends on:** C5, C11, C12
- **Statement:** The Today screen replaces the floating Microseason line with the resting
  **Year timeline** and, tapping it, expands the **Almanac** sheet showing the derived
  positions and copy — verified through the *real, reachable* live app (not merely that a
  view type exists).
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoUITests/MicroseasonAlmanacUITests` — expect `** TEST SUCCEEDED **`,
     exit 0, and `Executed [1-9][0-9]* test`. Launched with `KIGO_FAKE_DATE=2026-06-16`, the
     suite asserts via accessibility identifiers:
     - the resting state shows `microseason.sekki` (text contains 芒種), `microseason.ko`
       (text contains 梅子黄), and a tappable `microseason.timeline`;
     - tapping `microseason.timeline` presents `microseason.almanac`;
     - the almanac shows `microseason.koPosition` whose text contains both `27` and `72`, a
       `microseason.dayGauge`, and a non-empty `microseason.koDescription`;
     - dismissing (grab indicator or backdrop) hides `microseason.almanac`.

### C14: Image-attribution panel is reachable from Today

- **Depends on:** C5, C12
- **Statement:** An **(i)** control on the Today screen opens an **Attribution panel**
  showing the resolved image's credit — verified through the real app; dismissed by the grab
  indicator or backdrop (no label, no close button).
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoUITests/AttributionPanelUITests` — expect `** TEST SUCCEEDED **`,
     exit 0, and `Executed [1-9][0-9]* test`. Launched with `KIGO_FAKE_DATE=2026-06-16`, the
     suite asserts: `info.entry` is present; tapping it presents `info.panel`; the panel
     shows a non-empty `info.credit` and a non-empty `info.title`; dismissing via the
     backdrop hides `info.panel`.

### C15: Language preference switches the app's UI-chrome strings

- **Depends on:** C5, C9
- **Statement:** A persisted **Language preference** (Japanese default) drives the app's own
  UI-chrome strings, and the **Settings menu** exposes a JP/EN switcher; selecting English
  renders chrome in English. Content kanji names are unchanged and per-entry English content
  is deferred (ADR 0014) — only the mechanism, the chrome strings, and the switcher control
  are gated.
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoTests/LanguagePreferenceTests` — expect `** TEST SUCCEEDED **`, exit
     0, and `Executed [1-9][0-9]* test`. Driving the localized-strings seam over an injected
     store, the suite asserts: chrome strings (e.g. the Restore-purchases and loading labels)
     return their Japanese form by default; their English form when the preference is set to
     English; the selection persists across a re-read; and an absent/unrecognized value
     falls back to Japanese.
  2. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoUITests/SettingsLanguageUITests` — expect `** TEST SUCCEEDED **`,
     exit 0, and `Executed [1-9][0-9]* test`. Launching the real app and opening the Settings
     menu via `paywall.entry`, the suite asserts a `settings.language` switcher is present
     with a Japanese and an English option; and that launching with `KIGO_FAKE_LANGUAGE=en`
     renders a known chrome string in English (e.g. `paywall.restore` reads its English
     label) while the default launch renders it in Japanese.

### C16: Both appearances render without breaking (dark mode)

- **Depends on:** C5, C9
- **Statement:** The app follows the system **Appearance**; in **dark** appearance the Today
  screen and the Settings sheet still surface their key elements — no blank, broken, or
  crashed render. Visual fidelity of dark mode is J6, not gated here.
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoUITests/DarkModeUITests` — expect `** TEST SUCCEEDED **`, exit 0,
     and `Executed [1-9][0-9]* test`. Launched with `KIGO_FAKE_DATE=2026-06-16` and
     `KIGO_FAKE_APPEARANCE=dark`, the suite asserts the Today screen still shows `kigo.kanji`,
     `kigo.description`, `microseason.ko`, `info.entry`, and `paywall.entry`; and that tapping
     `paywall.entry` still presents `paywall.sheet` containing a non-empty `paywall.benefits`.

### C17: Asagiri fonts are bundled and registered (built-product wiring)

- **Depends on:** C1
- **Statement:** The Asagiri fonts ship inside the built app bundle and are registered in
  `UIAppFonts`, so the app uses them rather than silently falling back to the system font.
  (Whether the type *looks* right is J6; whether it is *wired* is gated here — the same
  built-product-wiring discipline as C8.)
- **Evidence:**
  1. Run `xcodegen generate`, then build with the product path pinned:
     ```
     perl -e 'alarm shift; exec @ARGV' 720 \
       xcodebuild build -scheme Kigo \
         -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
         -derivedDataPath build CODE_SIGNING_ALLOWED=NO
     ```
     — expect `** BUILD SUCCEEDED **` and exit 0.
  2. Assert the `UIAppFonts` array in the **built** app's Info.plist is non-empty with at
     least two entries:
     `/usr/libexec/PlistBuddy -c "Print :UIAppFonts:0" build/Build/Products/Debug-iphonesimulator/Kigo.app/Info.plist`
     and `:UIAppFonts:1` — expect both print a font filename (exit 0). *(Built-config wiring:
     an unregistered font silently never loads.)*
  3. For each filename printed in step 2, assert the file actually ships in the bundle:
     `test -f "build/Build/Products/Debug-iphonesimulator/Kigo.app/<that filename>"` — expect
     exit 0. *(Built-product wiring: the registered fonts are physically inside the shipped
     bundle, not merely referenced — the XcodeGen-silently-dropped-resource failure mode C8
     guards, applied to fonts.)*

### C18: Today screen composition (measurable visual facts)

- **Depends on:** C5
- **Statement:** The Today screen composes the Asagiri structure as objectively measurable
  facts: a **full-bleed** image filling the screen (not a small corner box — the exact bug
  the designer hit), a **legibility treatment** behind the centered text, and the controls in
  their corners (the **(i)** top-left, the **Settings gear** top-right). Aesthetic fidelity is
  J6; these geometric facts are gated.
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoUITests/TodayLayoutUITests` — expect `** TEST SUCCEEDED **`, exit 0,
     and `Executed [1-9][0-9]* test`. Launched with `KIGO_FAKE_DATE=2026-06-16`, the suite
     asserts against the app window's frame:
     - `kigo.image` is full-bleed — its width is within a small tolerance of the window width
       **and** its height is ≥ 90% of the window height (catches the "small box" regression);
     - a `kigo.scrim` legibility element is present in the hierarchy;
     - `info.entry`'s center is in the top-left region (x < width/2, y < height/3) and
       `paywall.entry`'s center is in the top-right region (x > width/2, y < height/3).

### C19: Manifest content is fully localized JP/EN, readings romanized (ADR 0018)

- **Depends on:** C2, C12
- **Statement:** Every localizable field in the Manifest is populated in **both** Japanese and
  English — Kigo/Kō/Sekki descriptions and glosses, attribution, and **readings** (`ja`=hiragana,
  `en`=romaji) — while kanji names stay single, untranslated values, and the schema still decodes
  with or without `en` (ADR 0014 forward-compat preserved). Translation *quality* is J2, not gated.
- **Evidence:**
  1. **Data-shape precheck (external, deterministic).** Run against `Resources/manifest.json`:
     ```
     python3 - <<'PY'
     import json, sys
     m = json.load(open('Resources/manifest.json'))
     def loc(x, path):
         assert isinstance(x, dict) and x.get('ja') and x.get('en'), f'{path} needs ja+en'
     for k, e in m['dailyMap'].items():
         loc(e['reading'], f'{k}.reading'); loc(e['description'], f'{k}.description')
         for f in ('title','credit','license'): loc(e['attribution'][f], f'{k}.attr.{f}')
         assert isinstance(e['kanji'], str) and e['kanji'], k          # kanji single value
     for o in m['ko']:
         loc(o['reading'], 'ko.reading'); loc(o['description'], 'ko.description')
     for s in m['sekki']:
         loc(s['reading'], 'sekki.reading'); loc(s['gloss'], 'sekki.gloss'); loc(s['description'], 'sekki.description')
     print('OK'); sys.exit(0)
     PY
     ```
     — expect `OK` and exit 0. *(Fails today: readings/description are plain strings and `en` is
     largely absent — reads unmet until the dataset is localized.)*
  2. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoTests/ContentLocalizationCompletenessTests` — expect `** TEST SUCCEEDED **`,
     exit 0, and `Executed [1-9][0-9]* test`. The suite loads the bundled Manifest through the decoder
     and asserts: every Daily-Map entry, Kō, and Sekki resolves a non-empty **English** value for each
     localizable field (description/gloss/reading/attribution); `kanji` is identical regardless of
     language; and the language accessor falls back to `ja` for a fixture entry that omits `en`
     (preserving the C12 / ADR 0014 forward-compat guarantee).

### C20: Language preference switches all content + chrome live (no relaunch — ADR 0018)

- **Depends on:** C13, C15, C19
- **Statement:** Toggling the Language preference in the **Settings menu** re-renders **every**
  visible string — Today (Kigo description, reading), the Almanac (Kō/Sekki gloss + prose), the
  Attribution panel, and UI chrome — from Japanese to English **without relaunch**, verified
  through the real, reachable live app. Kanji names are unchanged.
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoUITests/LiveLanguageSwitchUITests` — expect `** TEST SUCCEEDED **`, exit 0,
     and `Executed [1-9][0-9]* test`. Launched with `KIGO_FAKE_DATE=2026-06-16` (default Japanese,
     no `KIGO_FAKE_LANGUAGE`), the suite asserts via accessibility identifiers:
     - initially `kigo.description` reads its Japanese form (text contains the date `2026-06-16`,
       per C4) and `kigo.reading` shows the hiragana reading;
     - open the Settings menu (`paywall.entry`), select the English option on `settings.language`,
       dismiss — then **without relaunching**, `kigo.description` now reads its English form and
       `kigo.reading` shows romaji, while `kigo.kanji` is unchanged;
     - a known chrome string (e.g. `paywall.restore`) is in English after the toggle;
     - toggling back to Japanese restores the Japanese strings (the switch is reversible and live).

### C21: Manifest auto-updates from a versioned remote source (ADR 0017)

- **Depends on:** C3
- **Statement:** On app open the content store serves local content immediately and, in the
  background, checks a **versioned** `RemoteManifestSource`; it replaces the local copy **iff** the
  remote `version` is strictly newer and the body decodes/validates, and otherwise leaves the local
  copy untouched with no error surfaced to the UI. The update *logic* is gated headlessly through an
  injected fake (the real network fetch is off the gating path — J7 / ADR 0017).
- **Evidence:**
  1. Run the canonical test invocation (Constraints) with
     `-only-testing:KigoTests/RemoteManifestUpdateTests` — expect `** TEST SUCCEEDED **`, exit 0, and
     `Executed [1-9][0-9]* test`. With an injected fake `RemoteManifestSource` and an injected
     local cache (no live network, no `URLSession`), the suite asserts:
     - **newer:** local at `version` N, fake returns a valid manifest at N+1 ⇒ after the update check
       the local cache holds the N+1 manifest and a subsequent resolve returns N+1 content;
     - **not newer:** fake returns `version` ≤ N (or equal) ⇒ the local cache is unchanged;
     - **malformed / schema-mismatch:** fake returns undecodable or schema-mismatched data ⇒ the
       local cache is unchanged and no error is thrown to the caller;
     - **fetch fails:** fake throws (network error) ⇒ the local cache is unchanged, no error surfaces;
     - **non-blocking:** the store returns today's **local** content from the cache without awaiting
       the remote check (local content is available independent of the remote result).
  2. *(Residual on-path wiring, by inspection per ADR 0017.)* The production `RemoteManifestSource`
     is a thin `URLSession` adapter over a placeholder `https` URL constant; the comparison /
     apply / fallback logic it feeds is fully gated in step 1. The real end-to-end network fetch is
     J7, off the headless gating path.

## Judgment claims

Reported in the milestone report for async human review — never termination gates,
never autonomous certifications. (The user has opted out of a content-review gate;
these are surfaced for awareness only.)

### J1: The app reads as a calm, tasteful wellness object

- **Applies to:** whole project
- **Claim:** Opening the app feels contemplative and uncluttered — a single daily
  moment, dominated by the image and the word — not a utilitarian calendar.
- **Lens:** Launch the app in the simulator and judge typography, spacing, motion,
  and overall restraint as a non-developer seeking a calm daily ritual would.

### J2: The Kigo content and imagery are evocative and accurate

- **Applies to:** C2, C5, C12, C13, C14, C19
- **Claim:** The generated Kigo descriptions are accurate and evocative; the new per-Kō and
  per-Sekki almanac descriptions/glosses are accurate, in the right quiet voice, and give
  real "where am I in the year" context; the **English translations and romaji readings** are
  accurate and natural; the (currently placeholder) images and their (placeholder) attribution
  suit each Kigo and season. (The Daily-Map descriptions are currently instrumented dummy data
  carrying a date stamp — quality of the final curated corpus is judged when it lands.)
- **Lens:** Read a sample of Daily Map entries and almanac kō/sekki descriptions across
  seasons in **both languages** for accuracy and tone; view the rendered images and the
  attribution panel. Note that images, attribution values, and the dummy date-stamped Daily-Map
  copy are intentionally placeholders for now.

### J3: The widget renders correctly on a real home screen

- **Applies to:** C7, C8
- **Claim:** Added to a real device's home screen, both widget sizes (systemSmall and
  systemMedium) show today's Kigo name; a non-subscriber sees the name without the image,
  and a subscriber sees the image — i.e. the shared entitlement is actually enforced
  across the app↔widget process boundary and the gating works visually.
- **Lens:** On a signed device build, add both widget sizes to the home screen; confirm
  name-only for a free user, and the image revealed after purchase/restore. The
  home-screen render and real entitlement enforcement both need signing/provisioning and
  a human eye, so this is reported off the headless gating path — never a termination
  gate.

### J4: The real in-app purchase flow works end-to-end

- **Applies to:** C9, C10
- **Claim:** Through the live App Store path (not the injected fakes), the Paywall's
  buy button presents the real system purchase sheet; completing the purchase
  activates the **Entitlement** and unlocks the Widget image; the real price and
  duration load from the StoreKit `Product`; Restore re-establishes the entitlement;
  and the **Premium** manage affordance deep-links to the system-managed
  subscription screen. The placeholder Terms/Privacy URLs have been replaced with the
  real published documents before submission.
- **Lens:** In the Xcode IDE (Cmd+R / Cmd+U) with a `.storekit` configuration or a
  sandbox account — never the headless CLI — perform a purchase, a restore, and open
  manage; confirm the Entitlement and Widget Gate respond and the offer metadata is
  real. Off the headless gating path by construction (ADR 0009): the purchase sheet,
  real product loading, and manage deep link hang or need a human/account from
  `xcodebuild`, so this is reported for human review, never a termination gate.

### J5: The Paywall and Upgrade entry stay calm and on-brand

- **Applies to:** C9
- **Claim:** The Upgrade entry is unobtrusive enough to preserve the Today screen's
  calm nightstand feel (J1) — it reads as a quiet affordance, not an upsell badge —
  and the Paywall splash itself is tasteful, restrained, and on-brand rather than a
  pushy storefront.
- **Lens:** Launch the app; judge whether the Settings gear (the revamp's quiet
  replacement for the Upgrade entry) intrudes on the Today screen's restraint, then open the
  Settings menu and judge its typography, spacing, and tone as a calm-seeking, non-developer
  user would.

### J6: The revamp faithfully realizes the Asagiri direction in light and dark

- **Applies to:** C13, C14, C15, C16, C18, and the Today / Settings / Widget surfaces
- **Claim:** The implemented surfaces faithfully render the `Kigo Revamp.dc.html` Asagiri
  mockup — full-bleed photography under a feathered frosted-glass legibility plate; centered
  **Shippori Mincho** kanji at the specified type scale; the quiet **Year timeline** that
  taps to expand the almanac (positions, gauges, gloss, prose); the **(i)** attribution
  panel; the **Settings menu** (language / subscribe / legal); the gentle entrance motion;
  and the gated Widget — all in **both light and dark**, reading as the calm nightstand
  object (reinforcing J1/J5). Dark-mode polish (saturated season bands, warm-gold gloss, the
  scrim tuned per theme) is part of this claim.
- **Lens:** Launch in the simulator in **both** appearances against the design tokens in the
  handoff README; click through Today → Almanac, the (i) panel, and Settings (language toggle,
  subscribe/manage, legal); compare layout, color, Mincho type, scrim/plate legibility over a
  real photo, motion, and dark polish to `Kigo Revamp.dc.html`. Pixel-fidelity is reported
  for async human review — **never a termination gate** (the C* above gate the structure,
  data, wiring, and that both appearances render without breaking; the *look* is judged here).

### J7: The remote manifest update works end-to-end over the real network

- **Applies to:** C21
- **Claim:** Pointed at a real hosted versioned manifest, the app on open downloads a strictly
  newer version over the network, validates it, replaces the local copy, and shows the updated
  content on the next resolve — and on a real network failure (offline, 404, corrupt body) it
  silently keeps the local copy with no user-visible error. The placeholder remote URL constant
  has been replaced with the real published endpoint before submission.
- **Lens:** With a real manifest hosted at the configured URL (a higher `version` than the bundled
  seed), launch the app on a device/simulator with live networking and confirm the new content
  appears; then disable networking / point at a bad URL and confirm the app still shows local
  content. The live network fetch is off the headless gating path by construction (ADR 0017 /
  ADR 0001 — no live network in evidence procedures), so it is reported for human review, never a
  termination gate.
