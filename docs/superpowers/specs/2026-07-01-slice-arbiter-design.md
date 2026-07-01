# Slice-decomposition arbiter — autonomous resolution of critic-exhaustion halts

**Date:** 2026-07-01
**Status:** Design approved; pending implementation plan
**Scope:** The afk- loop's SLICE phase (`afk-slice`) and its halt routing in `afk-step`.

## Problem

When `afk-slice` decomposes a PRD, a clean-context **decomposer** proposes slices and a
clean-context **critic** gates them against the slicing rules. On a rule violation the
decomposer is re-dispatched with the critic's feedback, up to a budget of **≤2
re-decompositions**. If the critic still rejects after that, the loop records
`slice-critic-exhausted`, posts an `**afk-slice-blocked**` comment on the PRD, and writes
`.afk/BLOCKED` — a **hard stop** that halts the wrapper until a human leaves a
GitHub-visible resolution signal (a `## Decomposition note` / operator-amendment on the
PRD; editing the skill files does **not** count, because the loop can't see it).

This is the loop's single largest source of human toil. In the retrospective across 29
runs, SLICE held nearly all the wasted work: 6 `slice-critic-exhausted` events plus the
downstream `BLOCKED` halts they trigger (#37, #135, #162, #165). Reading the exhaustion
causes, they are **not one failure mode** — they split into three, each implying a
different resolver:

| Kind | Example | Root cause | Correct resolution |
|---|---|---|---|
| **critic-false-positive** | #37 | Critic mis-flagged a valid vertical sequence (extending a merged type) as a horizontal split | Override the critic; the decomposition was fine |
| **unsatisfiable-constraint** | #162 | Operator demanded a walking-skeleton first slice, but the work is atomically coupled | Relax a constraint (e.g. ship one atomic slice — see the `slice-deadlock-prefer-atomic` policy) |
| **goal-criterion-defect** | #165 | The GOAL criterion's acceptance test isn't machine-checkable | Fix the criterion **upstream in `docs/GOAL.md`** — the goal contract. The arbiter *proposes* the rewrite; a **human applies it** (see boundary below) |

A stronger model cannot satisfy a genuinely contradictory rule set, so this is **not** a
model-tier problem (do not "fix" it by upgrading the decomposer to opus). It is a
routing problem: on exhaustion the loop should *diagnose why* and, where it safely can,
*resolve it* — instead of always halting.

## Goals / non-goals

**Goals**
- On `slice-critic-exhausted`, resolve the contradiction autonomously where it is safe to
  do so, so most stuck PRDs proceed without waking a human.
- When a human genuinely must decide, halt with a **concrete proposed resolution** for
  one-click approval, not raw forensics to diagnose from scratch.
- Add no new infinite-retry surface; degrade to today's `BLOCKED` behavior on any
  miscalibration.

**Non-goals (YAGNI)**
- Proactive pre-decomposition contradiction linting. The existing decompose→critic loop
  is already a competent detector; a pre-check would need arbiter-tier reasoning on every
  SLICE run (~26) to save the ~6 stuck ones.
- Auto-mutating `docs/GOAL.md`. The goal contract is the human's; an agent must never
  rewrite the criteria it is later graded against.
- Any change to the healthy decompose→critic path.

## Design

### Trigger — reactive, on exhaustion only

Keep `decompose → critic → re-decompose (≤2)` exactly as-is. It fires the arbiter **only**
when that budget is exhausted. The three failed attempts are not waste: the *same standing
violation surviving all three* is precisely the evidence the arbiter needs to diagnose the
contradiction.

### The arbiter

A **clean-context `opus` subagent** — decorrelated from the sonnet-tier decomposer/critic,
mirroring the audit gate's rationale. Its prompt contains, verbatim and artifact-only:

- the PRD body (+ `## Fix scope` if present),
- the verbatim `<slicing-rules>` block,
- the critic's prompt,
- the **full rejection history**: every rejected decomposition and the critic's
  `violations` for each.

Framing: *"The slicer failed to produce a rule-compliant decomposition after N attempts.
Diagnose the root cause and decide a resolution."* It returns JSON:

```json
{
  "diagnosis": "critic-false-positive | unsatisfiable-constraint | goal-criterion-defect | other",
  "verdict":   "override-critic | relax-to-resolution | escalate-human",
  "directive": "<for override: the approved slice list; for relax: a concrete binding decomposition directive; for escalate: the concrete proposed resolution (proposed GOAL.md criterion rewrite, or proposed directive)>",
  "confidence": "<0-1 or low/med/high>",
  "rationale": "<why>"
}
```

Verdicts:
- **`override-critic`** — the last decomposition was actually rule-compliant; the critic
  mis-flagged it. `directive` = the approved slice list.
- **`relax-to-resolution`** — `directive` = a concrete binding decomposition directive
  (e.g. "ship as one atomic slice with these ACs"; "drop the walking-skeleton-first
  constraint for this PRD because …").
- **`escalate-human`** — used when `diagnosis = goal-criterion-defect`, **or** when the
  arbiter's confidence is low for any reason. `directive` = a concrete proposed resolution
  for one-click human approval.

**Hard boundary:** `diagnosis = goal-criterion-defect` can *only* produce
`escalate-human`. The arbiter never edits `docs/GOAL.md`; it only proposes the rewrite in
the halt forensics.

### Applying & recording the resolution (idempotency / loop-safety)

The arbiter posts its resolution as a **new GitHub-visible signal** on the PRD:
`**afk-arbiter** <verdict>: <directive summary>` carrying an
`<!-- afk-arbiter-resolution -->` marker. This slots directly into the *existing*
LOOP-STATE §3 mechanism ("re-enter SLICE only if a recognized resolution signal newer than
the block comment exists"), so re-entry is already bounded.

- **`override-critic` / `relax-to-resolution`** → `afk-slice` gets **exactly one** more
  `decompose + critic` pass, with the `directive` supplied as a binding constraint (or, for
  `override-critic`, the arbiter-approved list is published directly). If it *still* fails
  the critic → **real `BLOCKED`** (the arbiter was wrong; a human is genuinely needed).
- **`escalate-human`** → write `.afk/BLOCKED` as today, but the forensics carry the
  arbiter's concrete proposed fix, so the human approves/edits one directive instead of
  diagnosing from scratch.
- **One arbiter per exhaustion.** If an `afk-arbiter-resolution` marker already exists on
  the PRD and slicing failed again, do **not** re-arbitrate → `BLOCKED`. No new
  infinite-loop surface.

Net downside vs. status quo: one extra opus call on the ~6 stuck cases. Net upside: most
resolve without waking the operator; a wrong arbiter call degrades to exactly today's
`BLOCKED`.

### Code touch points

1. **`afk-slice` step 3** (exhaustion branch): replace "post `afk-slice-blocked` + halt"
   with "dispatch the arbiter, apply the verdict" (including the one-shot guard: skip if an
   `afk-arbiter-resolution` marker already exists → BLOCKED).
2. **`afk-step` LOOP-STATE §3**: register `**afk-arbiter**` / `<!-- afk-arbiter-resolution -->`
   as (a) a recognized resolution signal that permits SLICE re-entry, and (b) the one-shot
   guard against re-arbitration.
3. **Arbiter prompt**: a new sub-procedure in `afk-slice` (or a small `references/` file),
   defined verbatim like the critic prompt.
4. **Journal line**: `ARBITER | #<prd> | <verdict> | <diagnosis>` on every invocation, for
   post-hoc calibration review.

## Verification

The arbiter's decision is an LLM judgment call and must not gate any headless/CI path on a
live exhaustion (rare; and per the global testing rule, judgment seams are wrapped and
fenced off the gating path). Two layers:

1. **Golden-case fixtures — non-blocking calibration check.** Reconstruct 3–4 catalogued
   exhaustions as static fixtures = `{PRD body, slicing rules, critic prompt, recorded
   rejection history}` → expected `{diagnosis, verdict}`:
   - #37 → `critic-false-positive` / `override-critic`
   - #162 → `unsatisfiable-constraint` / `relax-to-resolution` (atomic)
   - #165 → `goal-criterion-defect` / `escalate-human` (never mutates GOAL.md)

   Run the arbiter prompt against each and assert it lands the right classification and
   verdict *shape*. This exercises the decision logic against known-answer inputs with no
   live loop, no GitHub, no simulator. Because it is a judgment call, it is a **manual /
   non-gating calibration lane**, same posture the loop takes toward judge panels — not a
   hard CI gate.

2. **Idempotency plumbing — deterministic hard gate.** The signal plumbing (arbiter marker
   recognized as a resume signal; one-shot guard blocking a second arbitration) is pure
   state-machine logic. Test it deterministically against fixture PRD states (marker
   present/absent × slicing pass/fail); this *can* gate.

## Rollout

Ship behind the existing signal vocabulary so it's incremental and observable. The
`ARBITER | …` journal line makes every firing auditable; after a few real invocations, the
operator can eyeball whether the arbiter's calls match what they'd have decided. If it
proves miscalibrated, disable is trivial (the exhaustion branch reverts to posting
`afk-slice-blocked`), and even while enabled a wrong verdict degrades safely to today's
`BLOCKED`.
