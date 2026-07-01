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

## Appendix: Task 5 — afk-slice step-3 exhaustion-branch edit

**File modified:** `~/.claude/skills/afk-slice/SKILL.md` (global, not git-tracked; backup at `SKILL.md.bak-2026-07-01`)
**Bullet location:** Step 3, "still failing after the budget" branch

### Before

```
- **still failing after the budget** → do not publish. A known-bad decomposition never reaches GitHub. Post `**afk-slice-blocked**: critic rejected <N> decompositions — <standing violations>` on the PRD and return a summary line `afk-step` records as a halt (`result=slice-critic-exhausted`). This is the slicing analogue of the loop's "self-heal within budget, then halt" policy.
```

### After

```
- **still failing after the budget** → do not publish; a known-bad decomposition never reaches GitHub. **First check the one-shot guard:** if this PRD already carries an `<!-- afk-arbiter-resolution -->` marker (the arbiter already ran and its resolution still failed the critic), do NOT arbitrate again — post `**afk-slice-blocked**: arbiter resolution exhausted — <standing violations>` and return a `result=slice-critic-exhausted` halt line. **Otherwise, dispatch the arbiter** per [`references/arbiter.md`](references/arbiter.md): it diagnoses the deadlock and returns a verdict. Apply the verdict exactly as that file's "How afk-slice applies the verdict" section specifies — `override-critic` publishes the arbiter's slice list; `relax-to-resolution` gets ONE more decompose+critic pass under the arbiter's binding directive (still failing → real halt); `escalate-human` writes the halt with the arbiter's proposed resolution in the forensics. Post the `**afk-arbiter**` + `<!-- afk-arbiter-resolution -->` comment and record `ARBITER | #<prd> | <verdict> | <diagnosis>` in the journal in all cases. Publishing after `override-critic`/successful `relax` proceeds to step 4.
```

### What changed

- Old: hard halt unconditionally on budget exhaustion (post `afk-slice-blocked`, record `slice-critic-exhausted`).
- New: check the one-shot guard first (if `<!-- afk-arbiter-resolution -->` marker already present → real BLOCKED), otherwise dispatch the arbiter per `references/arbiter.md`, apply its verdict (`override-critic` / `relax-to-resolution` / `escalate-human`), post the `**afk-arbiter**` + `<!-- afk-arbiter-resolution -->` comment, and record a `ARBITER | …` journal line in all cases.

---

## Appendix: arbiter.md (as shipped)

```
# Slice-decomposition arbiter

Invoked by `afk-slice` step 3 ONLY when the critic budget is exhausted
(`slice-critic-exhausted`). Purpose: diagnose why the slicer could not produce a
rule-compliant decomposition after 3 attempts, and decide a resolution — so the
loop resolves the ~common contradictions autonomously instead of always halting.

## Dispatch

Clean-context subagent, **`model: "opus"`** (pinned — decorrelated from the
sonnet decomposer/critic; never inherit `AFK_MODEL`). The prompt contains
*exactly*, artifact-only (no orchestration narrative, no "it went badly" framing):

1. the PRD body (+ `## Fix scope` / `## Decomposition note` if present),
2. the verbatim `<slicing-rules>` block from SKILL.md step 2,
3. the critic's prompt (from SKILL.md step 3),
4. the **full rejection history**: every rejected decomposition and the critic's
   `violations` for each round.

Followed by this instruction, verbatim:

> You are the arbiter. The slicer failed to produce a rule-compliant decomposition
> after 3 attempts; the rejected decompositions and the critic's violations for
> each are above. Diagnose the ROOT CAUSE of the deadlock, then decide a
> resolution. Classify the root cause as exactly one of:
> - `critic-false-positive`: the critic mis-applied a rule; the last decomposition
>   (or a specific one above) is actually rule-compliant. Growing an already-merged
>   type one behavior-per-slice, each with its own tests, is a VALID vertical
>   sequence — never a horizontal split.
> - `unsatisfiable-constraint`: a real constraint conflict makes any multi-slice
>   decomposition non-independently-verifiable (e.g. a required intermediate state
>   cannot compile or pass tests), OR an operator/PRD constraint directly
>   contradicts the slicing rules. The correct resolution is to relax the
>   least-important constraint — most often, ship one atomic slice rather than
>   force an artificial split.
> - `goal-criterion-defect`: the deadlock traces to the milestone's acceptance
>   criterion itself being underspecified or not machine-checkable, so no
>   decomposition can produce checkable acceptance criteria.
> - `other`: none of the above.
>
> Then choose a verdict:
> - `override-critic`: emit, in `directive`, the specific rule-compliant slice
>   list (as JSON) that should be published. Use ONLY when a decomposition above
>   genuinely satisfies the rules.
> - `relax-to-resolution`: emit, in `directive`, a single concrete binding
>   decomposition directive the decomposer must follow on one final attempt (e.g.
>   "ship as ONE atomic slice with these acceptance criteria: …"; or "drop the
>   walking-skeleton-first constraint for this PRD because …").
> - `escalate-human`: emit, in `directive`, a concrete PROPOSED resolution for a
>   human to approve in one edit (a proposed criterion rewrite, or a proposed
>   directive). You MUST choose this when `diagnosis = goal-criterion-defect`
>   (you may propose a `docs/GOAL.md` rewrite but MUST NOT apply it), and whenever
>   your confidence is low.
>
> Return ONLY this JSON:
> `{"diagnosis": "...", "verdict": "...", "directive": "...", "confidence": "high|medium|low", "rationale": "..."}`

## Verdict contract & invariants

(Verbatim from the plan's shared-interface section.)

- `diagnosis = goal-criterion-defect` ⟹ `verdict = escalate-human`.
- `confidence = low` ⟹ `verdict = escalate-human`.
- The arbiter never writes files; it only returns the JSON.

## How afk-slice applies the verdict

Post the resolution to the PRD as a comment (this is the durable signal the loop
re-derives from):

`**afk-arbiter** <verdict> (<diagnosis>, confidence <c>): <one-line directive summary>`
`<!-- afk-arbiter-resolution -->`
…followed by the full `directive` and `rationale`.

Then:
- **override-critic** → publish the `directive` slice list directly (skip a further
  critic round — the arbiter, a stronger decorrelated model, has overruled it).
- **relax-to-resolution** → run **exactly one** more `decompose + critic` pass with
  `directive` supplied as a binding constraint. Critic passes → publish. Critic
  still rejects → **real BLOCKED** (the arbiter was wrong; a human is needed).
- **escalate-human** → write `.afk/BLOCKED` with forensics that include the
  arbiter's `directive` (the proposed resolution) so the human approves/edits one
  thing rather than diagnosing from scratch.

**One-shot guard:** if the PRD already carries an `<!-- afk-arbiter-resolution -->`
marker and slicing has failed again, do NOT invoke the arbiter a second time →
**real BLOCKED**.

Record a journal line on every invocation:
`ARBITER | #<prd> | <verdict> | <diagnosis>`
```
