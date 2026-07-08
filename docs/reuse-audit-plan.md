# Reuse-audit execution plan

Companion to [reuse-audit-2026-07-07.md](./reuse-audit-2026-07-07.md). Sequences
that audit's three workstreams (in-repo fixes, playbook docs, template + tooling)
into one ordered plan.

**Driver:** ship a clean Kigo *and* harvest its reusable value.
**Destinations:** the harvested playbook and the versioned afk skills go to
**new dedicated repos** (not inside Kigo).
**Ordering principle:** do the in-repo fixes *before* harvesting, so the playbook
and template capture the corrected patterns — not the warts.

Effort tags: **S** ≈ <1h · **M** ≈ a few hours · **L** ≈ a day or more.

---

## Phase 0 — Preservation · ✅ DONE (2026-07-08)

The audit's #1 risk is loss, not bugs.

- [x] **Version the afk skills.** The 7 `afk-*` skills (+ `GOAL-FORMAT.md`,
  `LOOP-STATE.md`, `references/`, bundled `afk-init/scripts/afk-run.sh`) are
  version-tracked in private GitHub `aonsager/agent-skills`. *(audit T3)*
  - Constraint found: `~/.claude/skills` → `~/.agents/skills`, and the skill
    loader **does not follow directory symlinks** (nor discovers skills nested in
    a subfolder). So skills must stay flat + real in the live dir.
  - **Superseded 2026-07-08:** rather than a separate snapshot clone at
    `~/projects/afk-skills` (which needed manual re-sync after every edit), the
    **live dir `~/.agents/skills` is now itself the git working tree** — all 25
    personal skills tracked in place, repo renamed `afk-skills` → `agent-skills`.
    Workflow is edit-in-place → commit → push; **no sync step, no drift**. The
    old `~/projects/afk-skills` clone was deleted.
- [x] **Prune the stale worktree.** `.claude/worktrees/audit-189/` removed;
  `audit/189-review` branch ref preserved (its 5 unmerged C22 commits remain
  recoverable). *(audit Part 3 #5)*

## Phase 1 — Ship-blockers · gates App Store submission

- [x] **[M] H1 — compile-gate the fake resolvers behind `#if DEBUG`.** DONE
  (2026-07-08). Gated the `KIGO_FAKE_*` reads + fake types/helpers across 11
  files (2 KigoCore resolvers, 9 app-side); resolvers keep their signatures and
  fall through to production in Release. **Verified:** KigoCore fast lane 63
  tests green; Debug + Release app builds succeed; the Release `Kigo.app/Kigo`
  binary contains **0** `KIGO_FAKE` strings (Debug dylib keeps all 8). The
  `KIGO_FAKE_ENTITLEMENT`/`KIGO_FAKE_PURCHASER` premium bypass no longer ships.
  *(audit Part 3 #1; P1 amendment)*
- [ ] **⛔ BLOCKED — H2 — replace placeholder content.** Not a code fix; both
  halves depend on assets that don't exist yet (verified 2026-07-08):
  - **Manifest** (`Resources/manifest.json`) is still dummy instrumented data —
    `ja` descriptions carry English text + `(YYYY-MM-DD)` stamps, `dailyMap` is
    keyed by full dates instead of MM-DD, and `ko`/`sekki` are empty. The
    assemble gate has nothing to ship: the editorial store (`review.db`) has
    **0 of 365 days approved** and only 10 with an English description. Unblocks
    only when the content review (the `review-ui-redesign` branch's own work)
    completes; then run the assemble pipeline and swap the bundled manifest.
  - **App icon** (`AppIcon-1024.png`) is a correctly-sized 1024² PNG placeholder
    derived from `tsuyu.jpg`; replacing it needs a real designed icon (a design
    deliverable, deliberately not auto-generated for a shipping binary).
  *(audit Part 3 #2)*

## Phase 2 — Repo cleanup · ✅ DONE (2026-07-08) · precedes harvest so patterns are captured *corrected*

- [x] **[S] Resolve the public-vs-private contradiction.** Repo is **PUBLIC**
  (verified `gh repo view`); CLAUDE.md was correct. `.afk/INIT-NOTES.md` corrected
  (it claimed PRIVATE). Branch protection is available but not enabled
  (`GET /branches/main/protection` → 404) — note updated to say so. *(audit Part 3 #4)*
- [x] **[M] Finish the half-removed entitlement→widget path** (post-ADR-0019
  debris; ADR 0019 itself flagged this as optional YAGNI cleanup). Deleted
  `EntitlementSharedStore.swift` (protocol + `UserDefaultsEntitlementStore`),
  dropped the `store` seam + `refreshEntitlement()`/`restoreEntitlement()` from
  `EntitlementProvider`, removed the two no-op `WidgetCenter.reloadAllTimelines()`
  calls in `PaywallModel`, removed the vestigial app-group from both `project.yml`
  targets (+ orphaned `.entitlements`), fixed stale doc comments across widget +
  app, and updated all affected tests. **Verified:** KigoCore fast lane 59 green;
  sim lane PaywallTests 8/8 + PaywallPurchaseFlowTests 4/4; full scheme compiles;
  built `Kigo.app` carries no entitlements plist. *(audit Part 3 #3)*
- [x] **[M] Doc drift.** GOAL.md: Xcode 26.4 → 26.5 (runtime pin still 26.4),
  retired `perl -e alarm` / `name=…,OS=` command replaced by a reference to
  CLAUDE.md's canonical invocation (the single source) + de-retired the 2 build
  blocks; testflight.md: rewrote the pre-0019 widget-gated monetization to the
  ADR-0019 in-app-understanding model + dropped the App Groups capability note.
  `simulator-toolchain-handoff.md`'s `perl` command left as-is (dated forensic
  quote, not a living command). *(audit Part 3 #4)*
- [x] **[S] Hygiene.** `.gitignore`: added `.DS_Store` + `KigoCore/.swiftpm/`;
  `candidates.csv` added to `scripts/content/fill/.gitignore` (regenerable
  `fetch` output — audit's "pre-ADR-0025 legacy" call was wrong; it's current
  pipeline). `spine-sample.csv` decided = committed worked-sample (curated
  smoke-test spine, staged). Deleted the 6 superseded one-shot scripts
  (`add_ko_en`/`add_sekki_en`/`add_translation_en`/`localize_manifest`/
  `generate_daily_map`/`check_localization_completeness` — only peer + historical
  ADR/spec refs). Deleted the C2/C24 screenshot slice-evidence tests
  (`C2MigrationScreenshotTests` was coupled to the H2 dummy date-stamp;
  `C24AssembledManifestScreenshotTests` + its orphaned fixture). *(audit Part 3 #5)*

## Phase 3 — Playbook docs (P1–P10) · ✅ DONE (2026-07-08) · harvest, don't author

- [x] **[L] Write the ~10 stack-neutral pattern docs** into the new playbook
  repo. DONE. All 10 (P1–P10) harvested into
  **`~/projects/ios-starter/docs/playbook/`** (private GitHub
  `aonsager/ios-starter`) — the playbook shares the repo the Phase 4
  `ios-starter` template will use. Kigo constants stripped (domain, `KIGO_`
  prefix, product IDs, file lists, dated 26.4/26.5/simdiskimaged forensics —
  named only in each doc's Provenance line). "Habits to break" (Part 3) folded
  in as `## Guardrails`: compile-gate + speculative-seam→P1, halfway-extraction +
  copy-pasted-setup→P2, broad-permissions→P5, slice-number-narration→P7,
  outlived-evidence→P6, ChromeStrings-god-struct + god-views→P10. Each doc
  follows a shared `AUTHORING.md` contract. *(audit Part 1)*

## Phase 4 — `ios-starter` template + scripts · ✅ DONE (2026-07-08) · depends on 1–3

Assembled into **`~/projects/ios-starter/template/`** (pushed to private GitHub
`aonsager/ios-starter`, commit `5d04e0f`), harvested per a shared
`docs/template-authoring.md` conventions contract.

- [x] **[S] Consolidate `scripts/resolve-sim`.** DONE. One canonical
  `template/scripts/resolve-sim` reconciled from the 3 divergent copies; emits
  `platform=iOS Simulator,id=<UDID>` only (retired `name=…,OS=` form dropped),
  defaults to newest-available-iPhone with `SIM_NAME`/`SIM_RUNTIME` overrides,
  boots tolerantly. *(audit T2)*
- [x] **[S] Copy generic scripts.** DONE. `xctimeout`, `afk-tail.py`/`.sh`/
  `afk-watch.sh` copied verbatim; `afk-retro.py` line-23 hardcoded slug replaced
  with repo-derived slug (matching afk-tail.py). All executable, parse-clean. *(T2)*
- [x] **[L] Assemble the template.** DONE. `project.yml` skeleton (parameterized,
  teaching trap-comments kept, vestigial app-group + fonts/`.storekit` dropped);
  `AppCore/` Foundation-only package (**verified: 53 tests green, release build
  compiles the `#if DEBUG` seams out**); entitlement/paywall module with the
  **offer-display adapter finished** (production path now `Product`-backed via
  `displayPrice`/`subscriptionPeriod`; `"—"` reduced to a labeled nil-Product
  fallback); notification module; settings-store family (generic `Foo` template +
  applied appearance store); **shared `UITestCase` base** (fixes M5 — one
  launch/env-seed/date factory + dotted-a11y-id lookup); CLAUDE.md per P5; CI with
  the P3 silence-watchdog. App-side modules are inspected skeletons (won't compile
  standalone by design — only `AppCore` is on the fast lane). *(audit T1)*

## Phase 5 — afk engine hardening · last / ongoing

- [ ] **[M] Reconcile wrapper drift.** `afk-run.sh` is missing the documented
  `AFK_MAX_ITER` knob; split its generic driver from the iOS-simulator
  babysitting behind a stack hook; preserve the retro cost knowledge currently
  living only in comments. *(audit T3 remainder)*

---

## Dependency spine

```
Phase 0 ─┐
         ├─► Phase 2 ─► Phase 3 ─► Phase 4
Phase 1 ─┘
Phase 5  (standalone)
```

0 and 1 can run in parallel. 2 must precede 3 and 4 (harvest corrected
patterns). 3 feeds 4 (the CLAUDE.md skeleton + doc cross-references). 5 is
independent.
