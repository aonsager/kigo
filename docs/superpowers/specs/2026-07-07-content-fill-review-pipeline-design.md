# Content-fill review pipeline — design

**Date:** 2026-07-07
**Status:** approved for planning

## Problem

The `scripts/content/fill/` pipeline fills `content/kigo-2026.csv` (which
`assemble.py` turns into `Resources/manifest.json`) with sourced content for all
365 days of 2026. Today it is a chain of hand-run stage scripts writing CSVs,
with three separate inline-CSV human gates: review `spine-2026.csv` (readings /
placement), review `descriptions.csv` (prose), and pick images by putting `x` in
the `chosen` column of `candidates.csv`.

Two problems drive this work:

1. **No easy generation front door.** Running the year means invoking five
   scripts by hand with the right flags in the right order.
2. **The CSV chain conflates two data lifecycles.** Regenerable/derived data
   (spine facts, generated prose, fetched image candidates) and *editorial
   state* (human edits to prose, the chosen image, and approval) both live inline
   in the same CSVs. That breaks the moment you (a) regenerate a date range —
   you clobber human edits — or (b) put a web backend on top making cell-level
   writes.

We want: a small CLI wrapper with clean seams, a durable editorial store that
separates human decisions from regenerable output, and a local web UI that is
the single review surface for a day (readings + prose + image + approval).

## Decisions (settled during brainstorming)

- **Storage:** SQLite review store as the editorial source of truth, sitting
  between the generators and the `assemble.py` gate.
- **Scope:** storage + CLI wrapper + web review UI, designed together.
- **Web UI role:** a *unified per-day gate* — one review surface per day
  replacing all three inline-CSV passes; `approved` is a single per-day fact.
- **Web stack:** Python stdlib `http.server` backend + vanilla-JS SPA (no build
  step, matches the pipeline's stdlib-only ethos; Pillow stays the sole
  third-party dep).
- **Compile semantics:** *partial* — export only approved days in the range,
  report skipped unapproved ones (matches today's `build_csv`, which emits only
  fully-populated dates).
- **Regeneration rule:** *approved freezes* — approved days are never touched by
  `spine`/`generate`; unapproved days are drafts and fully regenerated;
  `--force` overrides.

## Architecture

```
                       fetch_spine + assign_dates (deterministic)
                                        │
                    fill.py spine ──────┴─────────▶ ┌─────────────────┐
                                                    │  review.db      │
        fill.py generate <range> ─── prose + ─────▶ │  (SQLite)       │
          (describe_via_claude,       candidates    │  days           │
           fetch_images fetch/crop)                 │  candidates     │
                                                    └────────┬────────┘
        fill.py review ── localhost web UI ◀────────────────┤
          (edit fields, pick image, approve day)            │
                                                            │  approved rows
        fill.py compile [range] ── DB→CSV export ──▶ content/kigo-2026.csv
                                                            │
                              scripts/content/assemble.py (UNCHANGED gate)
                                                            ▼
                                              Resources/manifest.json
```

### Two data lifecycles, one rule

- **Regenerable/derived:** spine facts, generated prose, fetched candidates.
  Deterministic, safe to re-run, throwaway.
- **Editorial state:** human edits to prose/readings, `chosen_candidate_id`,
  `approved`. The reviewer's work product; must survive regeneration.

The single rule that reconciles them everywhere: **approved freezes.** A day with
`approved=1` is never mutated by `spine` or `generate` (only `--force`
overrides). Unapproved days are drafts and are fully regenerated. This makes
regeneration safe and the reviewer's work durable, without per-field provenance
tracking.

## Data model — SQLite review store

Location: `scripts/content/fill/review.db` (gitignored). The exported
`content/kigo-2026.csv` remains the committed, git-diffable, shipped artifact;
the DB is working state. WAL mode so the web UI reads while `generate` writes.

**`days`**

| column | notes |
|---|---|
| `date` | PK, `YYYY-MM-DD` |
| `kanji`, `reading_ja`, `reading_en` | spine facts |
| `season`, `subseason`, `category`, `gloss_en` | spine facts / search helpers |
| `description_ja`, `description_en` | authored prose |
| `chosen_candidate_id` | FK → `candidates.id`, nullable |
| `approved` | 0/1, default 0 |
| `created_at`, `updated_at` | timestamps |

**`candidates`**

| column | notes |
|---|---|
| `id` | PK |
| `date` | FK → `days.date` |
| `provider` | pexels / pixabay / wikipedia |
| `source_url`, `attribution`, `license` | provenance |
| `local_path` | JPEG under `downloads/` |
| `width`, `height` | post-crop dimensions |
| `usable`, `note` | e.g. Wikipedia reference-only when license disallows |
| `rung` | which search rung surfaced it (kanji / gloss_en / romaji) |
| `is_wikipedia` | flags the accuracy-reference candidate |

One day → N candidate rows. Image bytes stay on disk (`downloads/`); the DB holds
paths + metadata only.

## CLI — one entrypoint `fill.py`, four subcommands

- **`fill.py spine [--force]`** — deterministic; seeds/refreshes the 365 `days`
  rows with facts (reuses `fetch_spine` + `assign_dates` logic via
  `store.seed_days()`). Skips approved days.
- **`fill.py generate --from DATE --to DATE [--no-images] [--no-descriptions]
  [--placeholder] [--force]`** — for each **unapproved** day in range: authors
  prose (`describe_via_claude`) and fetches image candidates (`fetch_images`
  fetch/crop), writing both into the store. Per-day failures are isolated and
  summarized at the end (same posture as the Wikipedia-isolation commit), never
  aborting the batch. `--placeholder` gives the keyless image path.
- **`fill.py review [--port N]`** — starts the local web server (see below).
- **`fill.py compile [--from DATE --to DATE] [--image-base-url URL]`** — exports
  **approved** days in range → `content/kigo-2026.csv` → `assemble.py` →
  `Resources/manifest.json`. Range defaults to the full spine. Unapproved days in
  range are skipped and reported on stderr (partial-manifest behavior). Zero
  approved days in range → message + non-zero exit.

## Reuse vs. refactor

The proven stage scripts stay the engine; the wrapper orchestrates them and
persists to the store. Lift each stage's pure core into an importable function,
keep I/O at the edges:

- `fetch_spine` + `assign_dates` → `store.seed_days()`
- `describe_via_claude` → `generate` ingests prose to the store
- `fetch_images` fetch/crop → `generate` writes candidate rows + JPEGs
- `build_csv`'s CSV-join → replaced by a DB→CSV export in `compile`
- **`assemble.py` is untouched — it stays the final gate.**
- `fetch_images.py select` becomes obsolete on this path (the chosen image is
  now `chosen_candidate_id` in the DB, set via the web UI).

The standalone CSV entry points may remain for ad-hoc use, but the wrapper is the
DB-backed path.

## Web review UI — stdlib server + vanilla JS

Backend: an `http.server`-based handler over `store.py`; localhost, single-user,
no auth. Frontend: one SPA (`web/index.html` + `app.js` + `style.css`), no build
step.

**API**

- `GET /api/days?from&to&status` → day summaries (date, kanji, approved,
  has_prose, has_image)
- `GET /api/days/{date}` → full day incl. candidate list with image URLs
- `PATCH /api/days/{date}` → update readings / JA+EN prose /
  `chosen_candidate_id` / `approved`; validates that `chosen_candidate_id`
  references a candidate belonging to that day
- `GET /candidates/{file}.jpg` → serves the JPEG from `downloads/`

**UI:** a filterable day list (by range + approval status) → click a day → an
editor panel showing readings, JA/EN prose textareas, candidate thumbnails as a
radio-select, and an **Approve** toggle. This single surface is the unified gate
replacing the three inline-CSV review passes.

## Concurrency

Single reviewer, single `generate` process. WAL mode makes concurrent reads
fine; the approve-freeze rule means `generate` skips approved days, so a reviewer
approving during a run is safe. Guidance: avoid running `generate` over a range
being actively reviewed.

## Testing & error handling

- `test_store.py` — seed, approve-freeze skip, range/status queries,
  export-approved. Pure Python, host-side (joins the existing
  `scripts/content/test_pipeline.py` / `test_fetch_images.py` suite).
- Command tests with a temp DB and the existing stubbed provider/LLM fakes.
- Web API tests hitting the handlers directly.
- `assemble.py` remains the end-to-end validation gate.
- Errors: missing API/provider keys → clear message (`--placeholder` for
  keyless); per-day `generate` failures isolated and summarized; `compile` with
  zero approved days in range → message + non-zero exit; web `PATCH` validates
  the referenced candidate and returns 4xx on a bad date/candidate.

## Non-goals

- Image re-hosting stays a post-`compile` step (the chosen JPEG is re-hosted at a
  stable base URL passed as `--image-base-url`); the pipeline does not host
  images.
- No multi-user auth or remote deployment — the UI is a local editorial tool.
- No per-field edit provenance — the approve-freeze rule is deliberately the only
  reconciliation mechanism.
