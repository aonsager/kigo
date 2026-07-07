# 0025 — SQLite editorial review store for the content-fill workflow

## Status
Accepted (2026-07-07)

## Context
The `scripts/content/fill/` pipeline filled `content/kigo-2026.csv` through a
chain of hand-edited CSVs with three inline human gates (spine readings, prose,
image selection). This conflated two data lifecycles: regenerable/derived data
(spine facts, LLM prose, fetched image candidates) and editorial state (human
edits, the chosen image, approval). Regenerating a date range clobbered human
edits, and a web review UI making cell-level writes over CSVs is race-prone; the
1-day→N-image-candidates relation already forced a separate `candidates.csv`.

## Decision
Introduce a SQLite store (`review.db`) as the editorial source of truth between
the deterministic generators and the untouched `assemble.py` gate. A `fill.py`
wrapper exposes `spine` / `generate <range>` / `compile [range]` / `review`; a
local stdlib web UI is the single per-day review surface (edit fields, pick
image, approve). One reconciliation rule — **approved freezes**: an approved day
is never mutated by `spine`/`generate` (only `--force`); unapproved days are
drafts, fully regenerated. `compile` exports only approved days to the existing
14-column contract CSV, so `assemble.py` remains the sole final gate.

## Consequences
- Regeneration is safe: human decisions survive re-runs without per-field
  provenance tracking.
- The DB is binary/not-diffable, so it is gitignored working state; the exported
  `content/kigo-2026.csv` stays the committed, diffable, shipped artifact.
- One DB↔CSV export boundary to maintain (in `store.export_rows` /
  `fill.write_contract_csv`), replacing the former multi-CSV join glue.
- The web UI is a local single-user tool (no auth, localhost) — see the spec
  `docs/superpowers/specs/2026-07-07-content-fill-review-pipeline-design.md`.
