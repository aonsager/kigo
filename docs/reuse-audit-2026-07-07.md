# Reuse audit — what to keep from Kigo, and how

Date: 2026-07-07. Produced from a five-track audit (testing/toolchain, afk loop,
app architecture, docs/process/content pipeline, and an adversarial warts hunt).

## TL;DR

Most of Kigo's transferable value is **knowledge, not code**. The two crown
jewels are (1) the **launch-environment-injected seam architecture** (every
non-deterministic dependency — StoreKit, clock, language, appearance, images,
notifications — behind a protocol with a production adapter, an in-memory fake,
and a pure `launch*(environment:)` resolver; ADR 0009 + 0013), and (2) the
**two-lane test topology** (Foundation-only local SPM package tested host-side
in <1s; simulator lane only for genuine UI). Everything else worth keeping is
either a small script, a config skeleton, or a documented trap.

Recommended vehicles, in priority order:

1. **A playbook repo/directory of pattern docs** (~10 docs, mostly already
   written here — harvest, don't author). Highest value per hour.
2. **An `ios-starter` template repo** — XcodeGen skeleton + `AppCore` package +
   generic modules as in-place source + CLAUDE.md skeleton + scripts + CI.
3. **Version the afk skills** — they live un-versioned in `~/.claude/skills/`
   with `.bak` files as the only history. This is the single biggest
   preservation risk: the loop engine is the most sophisticated artifact of
   this project and it isn't in any repo.

Do **not** publish the generic modules as standalone SPM packages yet — for a
solo/small team the maintenance tax outweighs the benefit until a second
project proves the boundary. Keep them as source inside the template.

---

## Part 1 — Keep as pattern docs (the playbook)

These are ideas/doctrines where the writing already exists in this repo and
just needs harvesting into stack-neutral (or at least project-neutral) docs.

### P1. Injectable-seam + launch-env doctrine ← ADR 0009, ADR 0013
The complete recipe for headless, deterministic iOS testing under an agent:
- Every external dependency is a `protocol: Sendable` seam with a thin
  production adapter ("correct by inspection"), an in-memory fake, and a pure
  `launch*(environment:) -> Seam` resolver reading a `<PREFIX>_FAKE_*` var.
- Real StoreKit purchases are **fenced off the automated path twice**: the
  integration target is excluded from the main scheme's test action AND every
  test self-skips unless `KIGO_RUN_STOREKIT_INTEGRATION=1` (set only by the
  dedicated scheme). Root cause worth preserving verbatim: `SKTestSession`
  under CLI `xcodebuild test` throws `SKInternalErrorDomain Code=3` or hangs
  against the production App Store — it only works via Xcode's IDE launch.
- Dotted accessibility identifiers (`paywall.buy`, `kigo.kanji`) as the sole
  UI-test assertion surface; type-agnostic lookup via
  `descendants(matching: .any).matching(identifier:).firstMatch` +
  `waitForExistence` (SwiftUI's element-type mapping is unstable).
- **Amendment for next time (H1 below): compile-gate the resolvers with
  `#if DEBUG`.** Kigo ships the fake resolvers — including an entitlement
  bypass — in Release. UI tests run debug builds, so gating costs nothing.

### P2. Two-lane test topology ← docs/kigocore-migration-plan.md
Already a near-perfect playbook: carve domain logic into a Foundation-only
local SPM package (dual iOS+macOS platforms so `swift test` runs host-side, no
simulator anywhere), keep a **`*TestSupport` library product** for fakes shared
across lanes (test targets can't import each other), run the fast lane first,
always. Includes the `Bundle.main` → injected-bundle trap and the app-group
UserDefaults trap. Strip the Kigo file lists.

### P3. CI hang-vs-slow separation ← .github/workflows/afk-ci.yml + CLAUDE.md
Three-tier model: per-test hang → XCTest execution-time allowance (120s);
runner/simulator wedge → **no-progress watchdog** (kill only after 300s of log
*silence* — healthy xcodebuild prints ~1 line/s); ultimate backstop → job
`timeout-minutes`. Never a fixed wall-clock cap on a growing suite (the PR #203
lesson). Plus the cost pattern: macOS minutes bill 10×, so the expensive gate
runs once per milestone (integration→main), not per slice.

### P4. Simulator durable rules ← CLAUDE.md, docs/simulator-toolchain-handoff.md
Separate the durable from the 2026-Apple-bug-specific:
- **Durable:** pin a concrete UDID, pre-boot, use `id=` destinations (never
  `name=…,OS=…` — it forces runtime enumeration through a cold
  CoreSimulatorService); never kill CoreSimulatorService as hygiene (that
  *manufactures* the wedge); the no-sudo recovery ladder (`killall -9
  CoreSimulatorService` → `simctl list` respawns → re-boot); runtime pin and
  toolchain version move independently.
- **Discard:** all iOS 26.4/26.5, iPhone 17, simdiskimaged specifics.

### P5. CLAUDE.md-as-trap-ledger format ← CLAUDE.md itself
The standout doc in the repo. The reusable skeleton: stack + toolchain pin
(with why + rollback); build/test lanes fastest-first with verbatim commands
and **exact success/failure strings** (`** TEST SUCCEEDED **`, `SimError 410`,
the "phantom 0 tests" false pass); a traps section where each trap = symptom
signature + measured verification with a date ("sandboxed → SimError 410 in
~60s; unsandboxed → SUCCEEDED in 12s, verified 2026-07-04") + the fix; recovery
ladder; war stories as guardrails so an agent won't rationalize around a rule.

### P6. GOAL.md format ← ~/.claude/skills/afk-goal/GOAL-FORMAT.md
The single most reusable idea in the loop: **every hard criterion carries an
inline, agent-executable evidence procedure with an exact pass observable**,
including anti-false-pass guards (`Executed [1-9][0-9]* test` so a vacuous
0-test run can't pass). Plus: hard out-of-scope fence, judgment claims (J*)
reported-not-gated, and the "split a flaky integration seam into logic-C* +
residual wiring check + off-path J*" rule.

### P7. ADR + CONTEXT.md practice ← docs/adr/, CONTEXT.md
The discipline, not the contents: rejected-alternatives sections; honest
`Supersedes`/`Reverses` headers; treating a dangling "see ADR NNNN" reference
as a bug to fix retroactively. CONTEXT.md's transferable tricks: the
**`_Avoid_:` forbidden-synonyms line** per term (prevents agent vocabulary
drift) and the **Flagged ambiguities** section recording resolved confusion.

### P8. Content pipeline blueprint ← ADR 0022 + ADR 0025 + content/README.md
For any LLM-drafted, human-reviewed content corpus:
- A deterministic, offline, idempotent **assemble-from-reviewed-source gate**
  (byte-identical re-runs, validates all rows before writing anything,
  fixture-tested refusals) — the shipped artifact is never hand-edited.
- A **SQLite editorial store separating derived data from human decisions**
  with the "approved freezes" reconciliation rule (regeneration never clobbers
  an approved day).
- Network/API-key/non-deterministic steps fenced off the automated path.
- A zero-dependency local review UI (stdlib `http.server` + vanilla JS, pure
  request handlers split from the socket adapter for testability).
- A documented legal posture for third-party source data (facts-only harvest
  at a pinned SHA, no copyrighted translations).

### P9. Widget architecture notes ← ADRs 0004, 0010, 0012, 0021
Pure `TimelineBuilder` (Foundation-only, Sendable) separated from the WidgetKit
shell so timeline logic unit-tests host-side; reload at next *local* midnight
via `entries[1].date`; bundle content into the appex so it renders with the app
process dead (the `_BundleAnchor` bundle-resolution trick); widget *gallery*
strings localized by device locale via `.xcstrings` + `CFBundleLocalizations`
(the gallery can't see in-app language state); don't put your only paid feature
in a widget — you can't deep-link a user to "add widget" (ADR 0019 reasoning).
Also the verify-widget techniques: flip app-group plist directly + bounce
`cfprefsd` to control widget state; never pass `CODE_SIGNING_ALLOWED=NO` when
the app-group entitlement matters.

### P10. Localization two-layer separation ← ADRs 0014, 0018, 0021
Data content localizes via the manifest (`LocalizedText { ja, en? }` — optional
field = additive change, no schema bump); UI chrome via an env-injected
preference (this is what makes **live in-app language switch without relaunch**
work); system surfaces via string catalogs. Keep the language-picker endonym
carve-out ("日本語"/"English" never localized). Do NOT carry the `ChromeStrings`
god-struct implementation (see B-list) — the layering is the keeper, not the
40-field hand-switched struct.

---

## Part 2 — Keep as code (the template repo + tools)

### T1. `ios-starter` template repo
Assemble from these pieces, with Kigo constants parameterized out:
- **`project.yml` skeleton** (app + embedded widget + unit/UI/widget tests +
  fenced StoreKit-integration target). Keep the inline trap comments — the
  "XcodeGen has no top-level `resources:` key" warning alone prevents a silent
  widget-resource drop. Cut: team ID, bundle IDs, fonts, `.storekit` file, and
  the now-vestigial app-group entitlement (dead since ADR 0019).
- **`AppCore/` package skeleton** (KigoCore minus domain): DateProvider,
  EntitlementProvider + seams, language/appearance/reminder store families,
  RemoteManifestSource, the ContentStore shape (loading/loaded/unavailable +
  deterministic `waitFor*()` test hooks), + `AppCoreTestSupport` product.
- **Entitlement + paywall module** (app-side): `StoreKitTransactionSource`,
  `SubscriptionPurchaser` + cancellation mapping, `PaywallModel`, the fake
  purchaser trio (`Fixed`/`Mutable` actor/`Flipping`/`Cancelling`), and
  `\.isEntitled` + `OpenPaywallAction` environment keys (the Sendable-wrapper
  idiom for a `@MainActor` action in the environment). Parameterize the product
  ID; **finish the offer-display adapter** (Kigo's production path still
  returns a hardcoded `"—"` price placeholder).
- **Notification module**: scheduler protocol + `UNUserNotificationCenter`
  adapter (lazy center) + cancel-then-schedule coordinator + launch resolver.
- **Settings store family template**: protocol + InMemory + `UserDefaults
  (suiteName:)` + `LockedInMemory` (UI-test pinning; `set()` no-op) + launch
  resolver — this is near-pure boilerplate, ideal template content.
- **Shared UI-test base class** (fix M5 in the template even though Kigo never
  did): app-launch factory with fake-env seeding + a shared Date factory, so
  the 97 copy-pasted setup sites don't recur.
- **CLAUDE.md skeleton** per P5, with the stack-specific traps pre-filled for
  iOS.
- **CI**: afk-ci.yml structure (runtime simulator resolver + silence watchdog)
  and slice-gate.yml (only if using the loop).

### T2. Scripts — copy nearly verbatim
- `scripts/xctimeout` — the name-anchored timeout wrapper. Its whole reason to
  exist is the Claude Code sandbox matching exclusions on the command string
  (raw `perl -e alarm xcodebuild` runs sandboxed → deterministic fake wedge).
  Keep the allowlist-of-toolchain-binaries design.
- `scripts/afk-tail.py` / `afk-tail.sh` / `afk-watch.sh` — fully generic
  observability for any Claude Code background loop; the cleanest code in the
  scripts dir.
- `scripts/afk-retro.py` — valuable cost/cache analyzer, but **fix line 23
  first**: the transcript path is hardcoded to this user+repo; it should reuse
  afk-tail.py's slug derivation.
- One consolidated `scripts/resolve-sim` — the repo currently has **three
  divergent copies** of the simulator resolver (CLAUDE.md, verify-widget.sh —
  which uses the *retired* `name=…,OS=` form, and afk-ci.yml). Write it once
  in the template.

### T3. The afk loop — version the engine
- The seven `afk-*` skills + `LOOP-STATE.md` + `GOAL-FORMAT.md` in
  `~/.claude/skills/` are generic by construction (they read stack specifics
  from the repo's CLAUDE.md/GOAL.md) and are the intended reuse path via
  `afk-init`. **They are not in any git repo and are hand-edited in place**
  (`.bak-2026-07-01` files). Move them into a versioned repo (dotfiles or a
  dedicated skills repo) before anything else.
- Reconcile the wrapper drift: `afk-run.sh` is missing the `AFK_MAX_ITER` knob
  the skill documents; split its generic driver (lock, timeout, cost parse,
  FAILING/WEDGED halt taxonomy) from the iOS simulator babysitting (put the
  latter behind a stack hook).
- Keep the retro knowledge that currently lives only in comments: orchestrator
  on Opus was ~73% of the token bill → cheap driver + model-pinned forks.
- Regenerate per project: GOAL.md content, arbiter fixtures, `.afk/` state.
  The `.afk/BLOCKED.*` post-mortems are worth a read before the next run.

### Explicitly NOT worth saving (trivial to rebuild or domain-bound)
Almanac resolution / 72-Kō ordering / manifest schema / DayKey; ChromeStrings
contents; PaywallView/TodayView styling; the encounter-vs-understanding
monetization framing (keep only the widget-discoverability reasoning);
`slice-gate.yml` outside the loop; all Xcode/iOS version pins and simdiskimaged
forensics; the one-shot migration scripts; kigo arbiter fixtures.

---

## Part 3 — Bad elements (fix, or at least don't preserve)

### Fix in this repo
1. **H1 — `KIGO_FAKE_*` resolvers compiled into Release, no `#if DEBUG`.**
   15 files, zero guards; `KIGO_FAKE_ENTITLEMENT=active` +
   `KIGO_FAKE_PURCHASER=succeed` are a premium bypass in the shipping binary
   (mitigated only by env injection requiring a debugger/jailbreak). Gate the
   resolver family behind `#if DEBUG`.
2. **H2 — Shipping placeholder content**: the bundled manifest is instrumented
   dummy data (date-stamped descriptions) and the app icon is a square crop of
   tsuyu.jpg. Ship-blockers if not already tracked; verify the assemble
   pipeline output has replaced the dummy manifest before submission.
3. **Half-removed entitlement→widget path** (post-ADR-0019 debris):
   `UserDefaultsEntitlementStore` is written but read by nobody;
   `WidgetCenter.reloadAllTimelines()` in `PaywallModel` is a no-op effect;
   `KigoWidget.swift` carries a stale doc comment claiming it reads the shared
   store; the app-group entitlement in project.yml is vestigial. Finish the
   removal.
4. **Doc drift**: GOAL.md Constraints still cite Xcode 26.4 and the *retired*
   `perl -e alarm` + `name=…,OS=` test command that CLAUDE.md explicitly
   deprecates; testflight.md still describes the pre-0019 widget-gated
   monetization. Also resolve the **public-vs-private contradiction**
   (.afk/INIT-NOTES.md says private; CLAUDE.md says public — screenshot embeds
   and branch-protection strategy both depend on which is true). Keep the
   canonical test command in exactly one place.
5. **Hygiene**: add `KigoCore/.swiftpm/`, `.DS_Store`, and
   `scripts/content/fill/candidates.csv` (legacy pre-ADR-0025 state — likely
   just delete it) to .gitignore; decide whether `spine-sample.csv` is a
   committed worked-sample or scratch; prune the stale
   `.claude/worktrees/audit-189/` worktree; delete the superseded one-shot
   scripts (`add_ko_en.py`, `add_sekki_en.py`, `add_translation_en.py`,
   `localize_manifest.py`, `generate_daily_map.py`,
   `check_localization_completeness.py`) after a reference grep; delete the
   C2/C24 screenshot slice-evidence tests (~95% duplicated harness views,
   attachments nobody asserts on).

### Habits to break in the next project
- **Test seams without compile gates** (H1) — the most important one.
- **Slice-number narration in doc comments** ("Slice #85 …") — changelog
  masquerading as current-state docs; it rots. Git history already has it.
- **Stopping module extraction halfway** — KigoFont/KigoTheme/KigoPlaceholder
  are file-shared across targets via project.yml source lists, the exact
  pattern KigoCore was created to eliminate.
- **God views** — TodayView's `body` is ~290 lines in one computed property.
- **Copy-pasted test setup** — 17 UI-test classes, no shared base, the same
  env seeding pasted ~97 times; UTC-calendar helper duplicated in 14 files.
- **Speculative seams carried as live code** — the ~900-line remote-image
  pipeline resolves to `nil` on every real launch (documented in ADR 0022, but
  don't mistake its passing tests for product coverage).
- **Overly-broad autonomous permissions** — `Bash(rm:*)` etc. auto-approved
  with `deny: []`; acceptable only in a dedicated experiment repo, and worth
  path-scoping next time.
- **Evidence artifacts that outlive their slice** — screenshot tests and
  always-green no-op checks need a scheduled deletion/review pass.
