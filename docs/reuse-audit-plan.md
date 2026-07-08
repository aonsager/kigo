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

- [x] **Version the afk skills.** 7 `afk-*` skills + `GOAL-FORMAT.md`,
  `LOOP-STATE.md`, `references/`, and the bundled `afk-init/scripts/afk-run.sh`
  moved into a dedicated git repo at `~/projects/afk-skills`, pushed to private
  GitHub `aonsager/afk-skills`. *(audit T3)*
  - Constraint found: `~/.claude/skills` → `~/.agents/skills`, and the skill
    loader **does not follow directory symlinks**. The repo is therefore a
    versioned snapshot; the live dirs stay real and must be **re-synced +
    committed after any skill edit**.
- [x] **Prune the stale worktree.** `.claude/worktrees/audit-189/` removed;
  `audit/189-review` branch ref preserved (its 5 unmerged C22 commits remain
  recoverable). *(audit Part 3 #5)*

## Phase 1 — Ship-blockers · gates App Store submission

- [ ] **[M] H1 — compile-gate the fake resolvers behind `#if DEBUG`.** 15 files,
  zero guards; `KIGO_FAKE_ENTITLEMENT=active` + `KIGO_FAKE_PURCHASER=succeed`
  are a premium bypass in the shipping binary. UI tests run debug builds, so
  gating is free. *(audit Part 3 #1; P1 amendment)*
- [ ] **[M] H2 — replace placeholder content.** Confirm the assemble pipeline
  output has replaced the dummy date-stamped manifest; replace the app icon
  (currently a square crop of `tsuyu.jpg`). *(audit Part 3 #2)*

## Phase 2 — Repo cleanup · precedes harvest so patterns are captured *corrected*

- [ ] **[S] Resolve the public-vs-private contradiction first.**
  `.afk/INIT-NOTES.md` says private, `CLAUDE.md` says public. Screenshot embeds
  + branch-protection strategy both depend on it. *(audit Part 3 #4)*
- [ ] **[M] Finish the half-removed entitlement→widget path** (post-ADR-0019
  debris): delete unread `UserDefaultsEntitlementStore`, the no-op
  `WidgetCenter.reloadAllTimelines()` in `PaywallModel`, the stale
  `KigoWidget.swift` doc comment, the vestigial app-group entitlement in
  `project.yml`. *(audit Part 3 #3)*
- [ ] **[M] Doc drift.** Fix GOAL.md (retired Xcode 26.4 + `perl -e alarm` /
  `name=…,OS=` command), testflight.md (pre-0019 monetization); collapse the
  canonical test command to exactly one place. *(audit Part 3 #4)*
- [ ] **[S] Hygiene.** `.gitignore` `KigoCore/.swiftpm/`, `.DS_Store`,
  `candidates.csv`; decide `spine-sample.csv` (sample vs scratch); grep-then-
  delete the 6 superseded one-shot scripts; delete the C2/C24 screenshot
  slice-evidence tests. *(audit Part 3 #5)*

## Phase 3 — Playbook docs (P1–P10) · harvest, don't author

- [ ] **[L] Write the ~10 stack-neutral pattern docs** into the new playbook
  repo. Strip Kigo constants + the "Explicitly NOT worth saving" list; fold the
  "Habits to break" (Part 3) in as guardrails inside the relevant docs. Now that
  fixes are done, the docs capture corrected patterns (P1 includes the
  `#if DEBUG` amendment, P10 warns off the ChromeStrings god-struct). *(audit
  Part 1)*

## Phase 4 — `ios-starter` template + scripts · heaviest lift; depends on 1–3

- [ ] **[S] Consolidate `scripts/resolve-sim`.** Three divergent copies exist
  today (CLAUDE.md, `verify-widget.sh` with the *retired* `name=…,OS=` form,
  `afk-ci.yml`). Write once. *(audit T2)*
- [ ] **[S] Copy generic scripts verbatim:** `xctimeout`, `afk-tail.py`/`.sh`/
  `afk-watch.sh`, `afk-retro.py` (**fix hardcoded path line 23** first). *(T2)*
- [ ] **[L] Assemble the template repo:** `project.yml` skeleton, `AppCore/`
  package, entitlement/paywall module (**finish the `"—"` offer-display
  adapter**), notification module, settings-store family, **shared UI-test base
  class** (fix M5 in the template even though Kigo didn't), CLAUDE.md skeleton
  (per P5), CI. *(audit T1)*

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
