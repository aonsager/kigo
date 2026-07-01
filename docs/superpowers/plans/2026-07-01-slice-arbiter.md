# Slice-Decomposition Arbiter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **⚠️ Superseded detail (implemented 2026-07-01):** this plan shows the arbiter journal line as the 4-field `ARBITER | #<prd> | <verdict> | <diagnosis>`. That form violated LOOP-STATE's mandatory six-field journal format and was reconciled during implementation to `<utc> | SLICE | #<prd> | arbiter-<verdict> | met=N/M | <diagnosis>; <directive summary>`. The shipped skill files and the design spec's "Journal-format reconciliation" note are authoritative; treat the 4-field occurrences below as historical.

**Goal:** On `slice-critic-exhausted`, dispatch a clean-context opus **arbiter** that diagnoses the contradiction and either resolves it autonomously (override the critic / relax to an atomic slice) with one bounded retry, or halts with a concrete proposed resolution — instead of always halting for a human.

**Architecture:** Reactive on exhaustion only. The existing `decompose → critic → re-decompose (≤2)` loop is unchanged and acts as the detector; its recurring standing violation is the arbiter's evidence. The arbiter is an opus subagent with an artifact-only prompt returning a JSON verdict. Its resolution is posted as a new GitHub-visible signal (`**afk-arbiter**` + `<!-- afk-arbiter-resolution -->`) that slots into the loop's *existing* resolution-signal + one-shot-guard machinery in `afk-step` LOOP-STATE §3.

**Tech Stack:** Markdown prompt-skills (`~/.claude/skills/afk-slice`, `~/.claude/skills/afk-step`); Python 3 for the calibration runner; `gh` CLI for fixture capture; GitHub issue comments as the loop's state channel.

## Global Constraints

- **The arbiter NEVER edits `docs/GOAL.md`.** `diagnosis = goal-criterion-defect` can ONLY produce `verdict = escalate-human`, carrying a *proposed* rewrite in the halt forensics. (Spec: "Never mutate GOAL.md.")
- **One arbiter per exhaustion.** If an `<!-- afk-arbiter-resolution -->` marker already exists on the PRD and slicing failed again → real `BLOCKED`. No second arbitration, ever.
- **Arbiter model is pinned `opus`** — decorrelated from the sonnet-tier decomposer/critic, never inheriting `AFK_MODEL`.
- **`~/.claude/skills/` is not git-tracked.** Every skill-file edit is preceded by a `.bak-2026-07-01` snapshot; the exact inserted text is recorded verbatim in this plan and the spec (the repo is the durable record). Skill files cannot be `git commit`-ed here — only repo files are committed.
- **The live-model calibration runner is a manual, non-gating lane** (an LLM-judgment seam per the global CLAUDE.md testing rule — wrapped, fenced off any CI/headless gating path). Only the deterministic fixture-shape check gates.
- All repo commits land on branch `design/slice-arbiter` (already created; holds the spec).
- Spec of record: `docs/superpowers/specs/2026-07-01-slice-arbiter-design.md`.

## The Arbiter Verdict Contract (shared interface)

Defined once here; consumed by `arbiter.md` (Task 2, produces it), the calibration runner (Task 3), and `afk-slice` SKILL.md (Task 4).

```json
{
  "diagnosis":  "critic-false-positive | unsatisfiable-constraint | goal-criterion-defect | other",
  "verdict":    "override-critic | relax-to-resolution | escalate-human",
  "directive":  "string — override-critic: the approved slice list as JSON; relax-to-resolution: a concrete binding decomposition directive; escalate-human: the concrete proposed resolution (proposed GOAL.md criterion rewrite, or proposed directive) for one-click human approval",
  "confidence": "high | medium | low",
  "rationale":  "string — 2-4 sentences"
}
```

Invariants (enforced by the prompt in Task 2 and asserted in Task 3):
- `diagnosis = goal-criterion-defect` ⟹ `verdict = escalate-human`.
- `confidence = low` ⟹ `verdict = escalate-human` (never gamble a resolution on low confidence).
- `override-critic` and `relax-to-resolution` are the only autonomous-resolution verdicts.

## File Structure

- **Create (repo):** `scripts/arbiter-fixtures/prd-37.json`, `prd-162.json`, `prd-165.json` — captured rejection histories + expected verdict. The known-answer corpus.
- **Create (repo):** `scripts/afk-arbiter-calibrate.py` — reads a fixture + `arbiter.md`, assembles the arbiter prompt, dispatches opus, prints verdict vs expected. Manual lane.
- **Create (repo):** `scripts/test_arbiter_fixtures.py` — deterministic (no LLM) shape/consistency check on the fixtures + contract invariants. The one gating test.
- **Create (skill):** `~/.claude/skills/afk-slice/references/arbiter.md` — the arbiter prompt, verdict contract, and application rules, verbatim.
- **Modify (skill):** `~/.claude/skills/afk-slice/SKILL.md` — step 3's "still failing after budget" branch: replace unconditional halt with arbiter dispatch + verdict application + one-shot guard.
- **Modify (skill):** `~/.claude/skills/afk-step/LOOP-STATE.md` — §3: register `**afk-arbiter**` as a recognized SLICE-re-entry signal AND the one-shot re-arbitration guard; add the `ARBITER | …` journal line to the record vocabulary.

---

### Task 1: Capture the golden-case fixture corpus

**Files:**
- Create: `scripts/arbiter-fixtures/prd-37.json`
- Create: `scripts/arbiter-fixtures/prd-162.json`
- Create: `scripts/arbiter-fixtures/prd-165.json`

**Interfaces:**
- Produces: three fixture files, each shaped:
  ```json
  {
    "prd": 162,
    "prd_body": "…verbatim PRD issue body (+ any ## Fix scope / ## Decomposition note)…",
    "rejection_history": "…verbatim afk-slice-blocked comment(s): each rejected decomposition + the critic's standing violations…",
    "expected": { "diagnosis": "unsatisfiable-constraint", "verdict": "relax-to-resolution" }
  }
  ```
- Consumed by Tasks 3 and 5.

- [ ] **Step 1: Pull the real PRD bodies and blocked comments**

Run (network → `dangerouslyDisableSandbox`):
```bash
for n in 37 162 165; do
  gh issue view $n --repo aonsager/kigo --json number,title,body,comments \
    > "scripts/arbiter-fixtures/raw-$n.json"
done
```
Expected: three `raw-<n>.json` files containing the full issue body and every comment (the `afk-slice-blocked` comments seen in recon are present).

- [ ] **Step 2: Build each fixture from the raw dump**

For each PRD, extract `body` and the `afk-slice-blocked` comment(s) verbatim into the fixture shape above. Set `expected` per the recon evidence:
- `prd-37.json` → `{"diagnosis":"critic-false-positive","verdict":"override-critic"}` (the blocked comment states the critic wrongly forbids extending an already-merged type — a false positive; the critic prompt has since been clarified to allow this).
- `prd-162.json` → `{"diagnosis":"unsatisfiable-constraint","verdict":"relax-to-resolution"}` (the blocked comment proves a walking-skeleton-first split cannot yield a green suite; only one atomic slice is verifiable).
- `prd-165.json` → `{"diagnosis":"goal-criterion-defect","verdict":"escalate-human"}` (a criterion's acceptance test is not machine-checkable — the defect is upstream in the criterion, which the arbiter may only propose to rewrite).

- [ ] **Step 3: Delete the raw dumps (keep only the curated fixtures)**

Run:
```bash
rm scripts/arbiter-fixtures/raw-*.json
```

- [ ] **Step 4: Commit**

```bash
git add scripts/arbiter-fixtures/prd-37.json scripts/arbiter-fixtures/prd-162.json scripts/arbiter-fixtures/prd-165.json
git commit -m "test(arbiter): capture golden-case exhaustion fixtures (#37/#162/#165)"
```

---

### Task 2: Write the arbiter prompt and application rules

**Files:**
- Create: `~/.claude/skills/afk-slice/references/arbiter.md`

**Interfaces:**
- Produces: `references/arbiter.md` containing (a) the verbatim arbiter prompt, (b) the verdict contract (copied from this plan's shared-interface section), (c) the application rules the SLICE phase follows per verdict.
- Consumed by Task 3 (calibration) and Task 4 (wiring).

- [ ] **Step 1: Write `references/arbiter.md`**

Create the file with exactly this content:

````markdown
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
````

- [ ] **Step 2: Snapshot is not needed (new file) — verify it renders**

Run:
```bash
wc -l ~/.claude/skills/afk-slice/references/arbiter.md && head -5 ~/.claude/skills/afk-slice/references/arbiter.md
```
Expected: the file exists, ~70+ lines, begins with `# Slice-decomposition arbiter`.

- [ ] **Step 3: Record the file verbatim in the spec (repo is the durable copy) and commit**

Append the full `arbiter.md` content under a new `## Appendix: arbiter.md (as shipped)` section in `docs/superpowers/specs/2026-07-01-slice-arbiter-design.md`, then:
```bash
git add docs/superpowers/specs/2026-07-01-slice-arbiter-design.md
git commit -m "docs(arbiter): record shipped arbiter.md prompt in spec appendix"
```

---

### Task 3: Deterministic fixture/contract check (the gating test)

**Files:**
- Create: `scripts/test_arbiter_fixtures.py`

**Interfaces:**
- Consumes: the fixtures from Task 1; the invariants from the shared contract.
- Produces: a `python3 -m pytest`-able (or plain-`assert`) check with NO LLM call.

- [ ] **Step 1: Write the failing test**

Create `scripts/test_arbiter_fixtures.py`:
```python
"""Deterministic checks on the arbiter fixture corpus and verdict contract.
No LLM call — this is the gating test. The live-model calibration lives in
afk-arbiter-calibrate.py and is explicitly non-gating."""
import json
from pathlib import Path

FIX = Path(__file__).parent / "arbiter-fixtures"
DIAGNOSES = {"critic-false-positive", "unsatisfiable-constraint",
             "goal-criterion-defect", "other"}
VERDICTS = {"override-critic", "relax-to-resolution", "escalate-human"}


def load():
    return [json.loads(p.read_text()) for p in sorted(FIX.glob("prd-*.json"))]


def test_three_fixtures_present():
    assert len(load()) == 3


def test_fixture_shape_and_values():
    for fx in load():
        assert isinstance(fx["prd"], int)
        assert fx["prd_body"].strip()
        assert fx["rejection_history"].strip()
        assert fx["expected"]["diagnosis"] in DIAGNOSES
        assert fx["expected"]["verdict"] in VERDICTS


def test_expected_verdicts_obey_invariants():
    for fx in load():
        d, v = fx["expected"]["diagnosis"], fx["expected"]["verdict"]
        if d == "goal-criterion-defect":
            assert v == "escalate-human", f"PRD {fx['prd']} violates GOAL.md boundary"


def test_all_three_categories_covered():
    diags = {fx["expected"]["diagnosis"] for fx in load()}
    assert {"critic-false-positive", "unsatisfiable-constraint",
            "goal-criterion-defect"} <= diags


if __name__ == "__main__":
    import sys
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn(); print(f"PASS {fn.__name__}")
    print("ALL PASS")
```

- [ ] **Step 2: Run it to verify it passes against Task 1's fixtures**

Run:
```bash
python3 scripts/test_arbiter_fixtures.py
```
Expected: `PASS test_...` for each, then `ALL PASS`. (If `test_all_three_categories_covered` fails, a fixture's `expected` was mis-set in Task 1 — fix the fixture, not the test.)

- [ ] **Step 3: Commit**

```bash
git add scripts/test_arbiter_fixtures.py
git commit -m "test(arbiter): deterministic fixture + contract-invariant checks"
```

---

### Task 4: Calibration runner (manual, non-gating lane)

**Files:**
- Create: `scripts/afk-arbiter-calibrate.py`

**Interfaces:**
- Consumes: a fixture (Task 1) + `~/.claude/skills/afk-slice/references/arbiter.md` (Task 2).
- Produces: assembles the arbiter prompt, dispatches opus via `claude -p`, prints `{prd, expected, actual, match}`. Never invoked by CI.

- [ ] **Step 1: Write the runner**

Create `scripts/afk-arbiter-calibrate.py`:
```python
"""MANUAL calibration lane for the slice arbiter — NON-GATING.
Dispatches the real opus arbiter prompt against a captured fixture and prints
its verdict next to the expected one. Live-model + nondeterministic: never run
this on a CI/headless gating path (global CLAUDE.md testing rule).

Usage: python3 scripts/afk-arbiter-calibrate.py [prd-162 ...]   (default: all)
"""
import json
import subprocess
import sys
from pathlib import Path

FIX = Path(__file__).parent / "arbiter-fixtures"
ARBITER = Path.home() / ".claude/skills/afk-slice/references/arbiter.md"


def build_prompt(fx):
    # arbiter.md holds the instruction; the fixture supplies the artifacts.
    return (
        f"{ARBITER.read_text()}\n\n"
        f"--- PRD BODY ---\n{fx['prd_body']}\n\n"
        f"--- REJECTION HISTORY ---\n{fx['rejection_history']}\n"
    )


def run(fx):
    out = subprocess.run(
        ["claude", "-p", build_prompt(fx), "--model", "opus",
         "--output-format", "json"],
        capture_output=True, text=True, timeout=300,
    ).stdout
    # extract the arbiter's JSON verdict from the CLI json envelope
    try:
        txt = json.loads(out).get("result", out)
    except json.JSONDecodeError:
        txt = out
    start, end = txt.find("{"), txt.rfind("}")
    return json.loads(txt[start:end + 1])


def main(names):
    files = ([FIX / f"{n}.json" for n in names] if names
             else sorted(FIX.glob("prd-*.json")))
    for p in files:
        fx = json.loads(p.read_text())
        v = run(fx)
        exp = fx["expected"]
        match = (v.get("diagnosis") == exp["diagnosis"]
                 and v.get("verdict") == exp["verdict"])
        print(f"PRD {fx['prd']}: expected={exp} actual="
              f"{{'diagnosis': {v.get('diagnosis')!r}, 'verdict': {v.get('verdict')!r}}} "
              f"-> {'MATCH' if match else 'MISMATCH'}")


if __name__ == "__main__":
    main(sys.argv[1:])
```

- [ ] **Step 2: Run the calibration against all fixtures (manual validation of the Task-2 prompt)**

Run (live opus; may take a few minutes):
```bash
python3 scripts/afk-arbiter-calibrate.py
```
Expected: three lines; the goal is `MATCH` on all three. A `MISMATCH` means iterate the `arbiter.md` prompt (Task 2) — this is calibration, not a gate. Record the observed verdicts in the PR description.

- [ ] **Step 3: Commit**

```bash
git add scripts/afk-arbiter-calibrate.py
git commit -m "test(arbiter): manual non-gating calibration runner"
```

---

### Task 5: Wire the arbiter into afk-slice step 3

**Files:**
- Modify: `~/.claude/skills/afk-slice/SKILL.md` (the step-3 "still failing after the budget" bullet)

**Interfaces:**
- Consumes: `references/arbiter.md` (Task 2), the verdict contract.
- Produces: the exhaustion branch now dispatches the arbiter and applies its verdict, with the one-shot guard.

- [ ] **Step 1: Snapshot the file (skills dir is not git-tracked)**

Run:
```bash
cp ~/.claude/skills/afk-slice/SKILL.md ~/.claude/skills/afk-slice/SKILL.md.bak-2026-07-01
```

- [ ] **Step 2: Replace the "still failing after the budget" bullet**

Find this exact line in `~/.claude/skills/afk-slice/SKILL.md` step 3:

> - **still failing after the budget** → do not publish. A known-bad decomposition never reaches GitHub. Post `**afk-slice-blocked**: critic rejected <N> decompositions — <standing violations>` on the PRD and return a summary line `afk-step` records as a halt (`result=slice-critic-exhausted`). This is the slicing analogue of the loop's "self-heal within budget, then halt" policy.

Replace it with:

> - **still failing after the budget** → do not publish; a known-bad decomposition never reaches GitHub. **First check the one-shot guard:** if this PRD already carries an `<!-- afk-arbiter-resolution -->` marker (the arbiter already ran and its resolution still failed the critic), do NOT arbitrate again — post `**afk-slice-blocked**: arbiter resolution exhausted — <standing violations>` and return a `result=slice-critic-exhausted` halt line. **Otherwise, dispatch the arbiter** per [`references/arbiter.md`](references/arbiter.md): it diagnoses the deadlock and returns a verdict. Apply the verdict exactly as that file's "How afk-slice applies the verdict" section specifies — `override-critic` publishes the arbiter's slice list; `relax-to-resolution` gets ONE more decompose+critic pass under the arbiter's binding directive (still failing → real halt); `escalate-human` writes the halt with the arbiter's proposed resolution in the forensics. Post the `**afk-arbiter**` + `<!-- afk-arbiter-resolution -->` comment and record `ARBITER | #<prd> | <verdict> | <diagnosis>` in the journal in all cases. Publishing after `override-critic`/successful `relax` proceeds to step 4.

- [ ] **Step 3: Verify the edit reads coherently and references resolve**

Run:
```bash
grep -n "afk-arbiter-resolution\|references/arbiter.md\|ARBITER |" ~/.claude/skills/afk-slice/SKILL.md
test -f ~/.claude/skills/afk-slice/references/arbiter.md && echo "arbiter.md present"
```
Expected: the grep shows the new marker, the reference link, and the journal-line token; `arbiter.md present`.

- [ ] **Step 4: Record the exact SKILL.md change in the spec and commit (repo files only)**

Add the before/after of this bullet to the spec's appendix, then:
```bash
git add docs/superpowers/specs/2026-07-01-slice-arbiter-design.md
git commit -m "docs(arbiter): record afk-slice step-3 exhaustion-branch edit in spec"
```
(The skill file itself is not committable here; the `.bak` snapshot is its rollback.)

---

### Task 6: Register the arbiter signals in afk-step LOOP-STATE §3

**Files:**
- Modify: `~/.claude/skills/afk-step/LOOP-STATE.md` (§3 SLICE routing / prior-slice-exhaustion guard, currently around line 54)

**Interfaces:**
- Consumes: the `**afk-arbiter**` / `<!-- afk-arbiter-resolution -->` signal produced by Task 5.
- Produces: the orchestrator recognizes the arbiter resolution as a SLICE-re-entry signal, and treats a second exhaustion-after-arbiter as BLOCKED.

- [ ] **Step 1: Snapshot the file**

Run:
```bash
cp ~/.claude/skills/afk-step/LOOP-STATE.md ~/.claude/skills/afk-step/LOOP-STATE.md.bak-2026-07-01
```

- [ ] **Step 2: Extend the recognized-resolution-signal list**

In §3's "Prior slice-exhaustion guard" paragraph, the recognized resolution signals list ends with option (c). Immediately after option (c)'s sentence, insert:

> Additionally, an **arbiter resolution** — an `**afk-arbiter**` comment carrying `<!-- afk-arbiter-resolution -->`, posted autonomously by `afk-slice`'s arbiter (see afk-slice step 3) — is a recognized resolution signal: it permits exactly ONE SLICE re-entry to apply the arbiter's directive. But if that re-entry also exhausts (an `afk-arbiter-resolution` marker is present AND a newer `afk-slice-blocked` comment exists), the arbiter has already had its one shot → **BLOCKED** (do not arbitrate or re-slice again). Unlike a skill-file change, this signal IS visible in GitHub state, so the loop may act on it without operator intervention.

- [ ] **Step 3: Add the ARBITER journal line to the record vocabulary**

Locate the journal-format description (the `PHASE | #issue | result | met | note` convention referenced in afk-step). Add one line documenting the arbiter record:

> `ARBITER | #<prd> | <verdict> | <diagnosis>` — emitted by `afk-slice` whenever the arbiter fires on exhaustion, for post-hoc calibration review.

- [ ] **Step 4: Verify coherence**

Run:
```bash
grep -n "afk-arbiter\|ARBITER |" ~/.claude/skills/afk-step/LOOP-STATE.md
```
Expected: the new resolution-signal sentence and the journal-line entry both appear.

- [ ] **Step 5: Record the exact LOOP-STATE change in the spec and commit**

Add the before/after to the spec appendix, then:
```bash
git add docs/superpowers/specs/2026-07-01-slice-arbiter-design.md
git commit -m "docs(arbiter): record afk-step LOOP-STATE signal registration in spec"
```

---

### Task 7: End-to-end dry-run of the exhaustion → arbiter path

**Files:** none (validation only)

**Interfaces:**
- Consumes: everything above.
- Produces: evidence that the wired path behaves as designed on a real fixture, without mutating live loop state.

- [ ] **Step 1: Dry-run the slicer against a known exhaustion fixture**

Using PRD #162's fixture (the clean `relax-to-resolution` case), dry-run `afk-slice` in exhaustion mode (per its "dry-run the slicer" affordance) against the fixture PRD body + rejection history — pointed at a scratch/no-write context so nothing is published. Confirm the trace shows: budget exhausted → arbiter dispatched (opus) → verdict `relax-to-resolution` → one binding decompose+critic pass → (publish or real-halt), and an `ARBITER | #162 | …` journal line.

Expected: the arbiter fires exactly once; on a second simulated exhaustion (marker present) the guard routes to BLOCKED without a second arbitration.

- [ ] **Step 2: Confirm the GOAL.md boundary holds**

Dry-run against PRD #165's fixture (goal-criterion-defect). Confirm the verdict is `escalate-human`, the forensics contain a *proposed* GOAL.md rewrite, and **no write to `docs/GOAL.md` occurs**.

Expected: `.afk/BLOCKED` forensics include the proposal; `git status` shows `docs/GOAL.md` unchanged.

- [ ] **Step 3: Record dry-run results and open the PR**

Summarize the two dry-runs (and the Task-4 calibration verdicts) in the PR body, then:
```bash
gh pr create --repo aonsager/kigo --base main --head design/slice-arbiter \
  --title "Slice-decomposition arbiter: autonomous critic-exhaustion resolution" \
  --body "Implements docs/superpowers/specs/2026-07-01-slice-arbiter-design.md. Skill-file edits (afk-slice, afk-step) are recorded verbatim in the spec appendix; .bak snapshots are the rollback. Calibration + dry-run results below."
```
(Network → `dangerouslyDisableSandbox`.)

---

## Self-Review

**1. Spec coverage** — every spec section maps to a task:
- Trigger (reactive-on-exhaustion) → Task 5 (SKILL.md branch fires only after budget).
- Arbiter subagent + JSON contract → Task 2 (`arbiter.md`), shared-interface section.
- Three verdicts + GOAL.md boundary → Task 2 prompt + Task 3 invariant test + Task 7 Step 2.
- Idempotency / one-shot guard / GitHub signal → Task 5 (guard) + Task 6 (LOOP-STATE recognition).
- Code touch points (afk-slice, afk-step, arbiter prompt, journal line) → Tasks 2/5/6.
- Verification: golden-case fixtures → Tasks 1/4; deterministic plumbing gate → Task 3; dry-run → Task 7.
- Rollout (journal `ARBITER` line, safe degradation) → Task 6 Step 3, Task 5 Step 2.

**2. Placeholder scan** — no TBD/TODO; all prose inserts and code are verbatim; fixture `expected` values are concrete (grounded in the recon of the real blocked comments).

**3. Type consistency** — the verdict field names (`diagnosis`, `verdict`, `directive`, `confidence`, `rationale`) and their enum values are identical across the shared-interface section, `arbiter.md` (Task 2), `test_arbiter_fixtures.py` (Task 3), and `afk-arbiter-calibrate.py` (Task 4). Signal tokens (`**afk-arbiter**`, `<!-- afk-arbiter-resolution -->`, `ARBITER | #<prd> | <verdict> | <diagnosis>`) are identical across Tasks 2/5/6.

**Known caveat carried from the spec:** the two live-model steps (Task 4 calibration, Task 7 dry-run) are LLM-judgment seams — non-gating by design and never on a CI/headless path (global CLAUDE.md rule). Only Task 3 gates.
