# Content-fill tool → text-only editorial — design

**Date:** 2026-07-23
**Status:** Approved (brainstorming) — ready for implementation plan
**Depends on:** the Sekki-backdrop image pivot (spec `2026-07-22-sekki-backdrop-image-pivot-design.md`, ADR 0026) — this is the `scripts/content/fill/` follow-up that pivot explicitly deferred.

## Problem

The image pivot (ADR 0026) removed per-day images from the whole app and stripped
the image columns from the assembly contract (`csv_parser.py` is now 7 columns;
`assemble.py` dropped `--image-base-url`). It deliberately left
`scripts/content/fill/` — the content-authoring + review tool — untouched, which
leaves it **broken against the new contract**:

1. `fill.py compile` forwards `--image-base-url` to an `assemble.py` that no longer
   accepts it → nonzero exit.
2. `store.export_rows` skips any approved day without a `chosen_candidate_id`, so with
   images obsolete **compile exports 0 rows**.
3. `fill.py`/`store.py`/`build_csv.py` still import and emit the deleted image
   machinery (`fetch_images`, `image_id`, `attribution_*`).

The tool's entire image half (Pexels/Pixabay/Wikipedia candidate ladder, smart-crop,
download, candidate selection) existed to source *per-day images* — the exact thing
that didn't scale and drove the pivot. It is now dead weight.

The user wants to **keep the tool as a way to review the daily Kigo** — specifically
**editorial** review of the text content (kanji, readings, translation, descriptions),
not visual preview.

## Decision summary

Descope `scripts/content/fill/` to a **text-only editorial pipeline**. Same four-verb
shape (`spine` → `generate` → `review` → `compile`), with every image concern removed
and the contract boundary repaired. Preserve the existing `review.db` editorial content
via a real migration.

## What the tool becomes

Four subcommands over the SQLite store (`review.db`), run as
`python3 scripts/content/fill/fill.py <cmd>`:

- **`spine`** — unchanged. Seeds 365 day-fact rows.
- **`generate --from --to`** — **prose only**. The image half (`generate_images`) and all
  image flags (`--primary/--fallback/--no-images/--no-wikipedia/--candidates/--min-width`
  …, `--out-images/--images`) are removed. Because prose is now the only phase,
  `--no-descriptions` is removed too. `--from/--to` and the "approved days are frozen
  unless `--force`" reconciliation rule stay. Still calls Claude for
  `description_ja`/`description_en` via the existing `generate_descriptions`.
- **`review`** — the local web SPA becomes a clean **per-day editorial editor**:
  - read-only facts: `kanji`, `reading_ja`/`reading_en` (shown), `gloss_en`, season tags;
  - editable: `reading_ja`, `reading_en`, `translation_en`, `description_ja`,
    `description_en`;
  - approve / unapprove;
  - the index list keeps a `has_prose` + approved indicator.
  Removed: the candidate gallery, the `/candidates/<id>.jpg` route, the `has_image`
  dots, and `chosen_candidate_id` from the PATCH whitelist.
- **`compile`** — exports approved days to the **7-column** contract CSV
  (`content/kigo-2026.csv`), then shells out to `assemble.py`. The `--image-base-url`
  forwarding is removed.

**`compile` behavior is intentionally left as-is:** `assemble.py` still *replaces* the
whole `dailyMap` from the approved rows (pre-existing behavior, unchanged by this work),
so publishing remains all-or-nothing — a complete manifest ships only once the full year
is approved. Reworking that into an incremental merge is explicitly out of scope.

## Data migration (preserve `review.db`)

`review.db` (gitignored, at `scripts/content/fill/review.db`) may hold real editorial
work (written descriptions, approvals). The migration must keep **every `days` row**:

- Drop the `candidates` table.
- Drop the `chosen_candidate_id` column from `days` (SQLite ≥ 3.35
  `ALTER TABLE days DROP COLUMN chosen_candidate_id`; fall back to the standard
  create-new-table / copy / swap rebuild if the runtime SQLite is older).
- Leave all fact, prose, and `approved` values untouched.

The migration is idempotent (safe to run on an already-migrated DB and on a fresh
`spine`-seeded DB) and runs automatically on store open (schema-version guarded) so a
user with an existing DB does not have to invoke it manually.

**Behavior change — the ship gate.** `store.export_rows` currently skips any approved
day lacking a `chosen_candidate_id` (this is what makes `compile` emit 0 rows today). It
is re-gated to export approved days by **prose completeness**, defined as the fields the
current contract/validator (`csv_parser.py` + `validator.py`) require of a valid row —
so a day that would pass `assemble.py` is exportable and one that would fail is skipped.
The plan pins the exact required fields against `validator.py` (the single source of
truth: e.g. `reading_ja`/`description_ja`/`description_en` required, `reading_en`/
`translation_en` per their existing optional status — ADR 0014). Images are no longer
part of the gate.

## What gets deleted

- `fetch_images.py` (entire file — provider ladder, Wikipedia rung, smart-crop, download,
  candidate selection) and `test_fetch_images.py`.
- The `downloads/` directory and `candidates.csv`.
- The `candidates` table and its store functions: `add_candidate`, `get_candidates`,
  `clear_candidates`, `set_chosen`, and the image portions of `_contract_row` /
  `export_rows` / `pending_dates`. Remove the module-load imports of `fetch_images` and
  the image half of `build_csv` from `store.py`.
- `build_csv.CONTRACT_COLUMNS` image columns (`image_id`, `attribution_title_ja/_en`,
  `attribution_credit_ja/_en`, `attribution_license_ja/_en`) → the 7 text columns only
  (`date, kanji, reading_ja, reading_en, translation_en, description_ja,
  description_en`); the image-join logic in `build_csv.py main` and `fill.py
  write_contract_csv`.
- `webapp.py`: the `/candidates/<id>.jpg` route, `has_image`/`candidate_count` in
  `day_summary`, and `chosen_candidate_id` from the PATCH whitelist.
- `web/app.js` `renderCandidates` + the candidate/gallery CSS in `web/style.css`; the
  "choose one image" empty-state copy in `web/index.html`.
- The image-specific test cases inside `test_store.py`
  (`test_add_and_get_candidates`, `test_set_chosen_*`, `test_clear_candidates_*`,
  `test_export_rows_only_approved_with_chosen`), `test_webapp.py`
  (`test_get_day_includes_candidates`, the candidate assertions in
  `test_day_summary_flags`/`test_patch_day_*`), and `test_fill.py`
  (`test_generate_images_*`, `test_compile_writes_contract_csv_and_copies_image`).

**Kept as-is (not image-coupled):** `fetch_spine.py`, `assign_dates.py`, `describe.py`,
`describe_via_claude.py`, `spine_pool.json`, `spine-2026.csv`, and every prose/review/
approve test.

## Contract boundary (the repair)

After this work `fill/` emits the **same 7-column CSV** that `csv_parser.py` /
`assemble.py` now expect, from `store.export_rows`. `write_contract_csv` and
`build_csv.CONTRACT_COLUMNS` both reduce to those 7 columns. `compile` invokes
`assemble.py --csv … --out …` with no image flag. Result: `compile` on a DB with
approved, prose-complete days produces a valid manifest end-to-end.

## Docs

- Rewrite `scripts/content/fill/README.md`: remove the image stages (fetch/select),
  the "legal posture"/attribution sections, and the image flags; describe the text-only
  `spine → generate → review → compile` flow and the 7-column contract.
- Update `content/README.md` where it documents the old 14-column contract.
- Record the descoping in the decision log: a short note appended to ADR 0026 (or a small
  new ADR "content-fill tool descoped to text-only editorial") so this is on record with
  the rest of the pivot.

## Out of scope

- Any change to `assemble.py`/`csv_parser.py`/`validator.py` (already correct post-pivot)
  — `compile`'s replace-not-merge behavior stays.
- Any change to the shipped app, widget, or `Resources/manifest.json`.
- Sourcing the 24 per-Sekki backdrop images (a separate out-of-band task; the fill tool
  has no role in it).
- Reviving image sourcing in any form.

## Success criteria

- `python3 scripts/content/fill/fill.py compile` on a `review.db` with at least one
  approved, prose-complete day writes a valid 7-column `content/kigo-2026.csv` and a
  manifest via `assemble.py`, exit 0 — no `--image-base-url`, no 0-row skip.
- The migration run against an existing `review.db` keeps every `days` row and its prose/
  approvals, dropping only the `candidates` table and `chosen_candidate_id`.
- `review` serves a text-only editorial editor (edit readings/translation/descriptions,
  approve) with no candidate/image UI or routes.
- All remaining `fill/` tests pass (`test_store`, `test_fill`, `test_webapp`); the
  image-only test files/cases are gone; no `fill/` module imports `fetch_images` or emits
  image columns.
- `grep` shows no `image_id`/`attribution`/`chosen_candidate_id`/`candidates`/
  `--image-base-url`/`fetch_images` reference remaining as live code under
  `scripts/content/fill/`.
- READMEs describe the text-only flow + 7-column contract; the descoping is recorded in
  the decision log.
