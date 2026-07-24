# kigo-2026 fill workflow

Fills `content/kigo-2026.csv` — the reviewable source CSV the deterministic
`scripts/content/assemble.py` pipeline turns into `Resources/manifest.json`
(ADR 0022) — with real, sourced content for all 365 days of 2026.

This is the concrete implementation of the "LLM-fill workflow" sketched in
`content/README.md`. It splits the job into small, reviewable stages so the one
step that *must* stay human (reading the Japanese) is the only manual gate.

**Text-only.** Earlier revisions of this tool also sourced and reviewed a
per-day photograph (Pexels/Pixabay/Wikipedia candidates, an image-candidate
picker in the review UI, `--image-base-url`). ADR 0026 retired per-day
photography in favor of 24 bundled per-Sekki backdrop images shipped in the
app binary, which made that whole half of the tool obsolete; it has been
removed. This tool now only authors and reviews the **text** columns —
readings, translation, and bilingual descriptions.

```
                 brokyo/saijikijs kigo.json @ pinned SHA
                                 │
        (1) fetch_spine.py  ── factual fields only ──▶ spine_pool.json
                                 │
        (2) assign_dates.py ── 365-day placement ────▶ spine-2026.csv  ◀── human review
                                 │
        (3) describe.py     ── emit ▶ LLM ▶ ingest ──▶ descriptions.csv
                                 │
        (5) build_csv.py    ── join on date ──────────▶ content/kigo-2026.csv
                                 │
                     scripts/content/assemble.py  ── the real gate ──▶ manifest.json
```

(Stage 4 — image sourcing — no longer exists; the numbering gap is left as-is
because `build_csv.py`'s own docstring still calls itself "stage 5".)

## The wrapper (recommended) — `fill.py` + web review

`fill.py` orchestrates the stages above over a SQLite review store
(`review.db`, gitignored) and a local web review UI. See ADR 0025. Four
subcommands:

```bash
# 1. seed the 365 day facts (deterministic; consumes spine_pool.json)
python3 scripts/content/fill/fill.py spine

# 2. generate prose for a date range (unapproved days only; reads
#    ANTHROPIC_API_KEY from the gitignored scripts/content/fill/.env — a real
#    exported env var overrides the file)
python3 scripts/content/fill/fill.py generate --from 2026-03-01 --to 2026-03-31

# 3. review in the browser: edit readings/translation/descriptions, approve each day
python3 scripts/content/fill/fill.py review        # http://127.0.0.1:8000

# 4. compile approved + prose-complete days → content/kigo-2026.csv → manifest
#    (the assemble gate)
python3 scripts/content/fill/fill.py compile
```

Useful flags: `generate --force` includes already-approved days (normally
skipped); `generate --model` overrides the Claude model. `compile --from/--to`
restricts the exported date range, `--out-csv`/`--manifest-out` redirect the
outputs (defaults: `content/kigo-2026.csv` / `Resources/manifest.json`).
`review --host/--port` change the bind address/port (default binds
`0.0.0.0:8000` — all interfaces, reachable on your LAN).

"Approved freezes": `spine`/`generate` never touch an approved day (use
`--force` to override). `compile` exports only days that are **both approved
and prose-complete** — every one of `kanji`, `reading_ja`, `reading_en`,
`translation_en`, `description_ja`, `description_en` non-empty, mirroring the
same gate `scripts/content/validator.py` re-checks at assembly — reporting any
skipped day on stderr. The per-stage scripts below remain for ad-hoc use.

Until a day is approved, `generate` treats it as a draft and fully
regenerates its prose on every re-run, so any manual edits made before
approval are discarded; approve the day first to freeze it against
regeneration.

### `review.db` migration

`review.db` (gitignored) is versioned with `PRAGMA user_version`. Connecting
with an older (v0, pre-ADR-0026) database automatically and idempotently
migrates it forward — dropping the retired `candidates` table and
`chosen_candidate_id` column while preserving every `days` row — before any
command runs. No manual migration step is required; just keep using `fill.py`
against your existing `review.db`.

## What you must supply

| Input | For | How |
|---|---|---|
| **An LLM** (stage 3 / `generate`) | authoring `translation_en` / `description_ja` / `description_en` | any capable chat model, or `ANTHROPIC_API_KEY` (put it in the gitignored `scripts/content/fill/.env`, or export it) + `describe_via_claude.py` |
| **A Japanese-literate reviewer** | the human gate on readings + descriptions | read top-to-bottom in the `review` web UI (or `spine-2026.csv`/`descriptions.csv` for the ad-hoc scripts), correct inline, approve |

Everything else runs offline with the Python stdlib — no third-party
dependencies.

## Run it

### The deterministic spine (free, no keys) — do this first, for the whole year

```bash
python3 scripts/content/fill/fetch_spine.py  --out scripts/content/fill/spine_pool.json
python3 scripts/content/fill/assign_dates.py --pool scripts/content/fill/spine_pool.json \
                                             --out  scripts/content/fill/spine-2026.csv
```

`spine-2026.csv` is now 365 rows of `date, kanji, reading_ja, reading_en` (+
`season / subseason / category / gloss_en` helper columns). **Have a
Japanese-literate reviewer check it before drafting prose** — fix any reading or
seasonal-placement you dislike here, once, at the source.

Placement is documented and deterministic (same source → byte-identical CSV):
the 24 Sekki (from the bundled manifest, risshun-anchored per ADR 0015) decide
each day's season; New Year kigo fill the opening week of January
(`--new-year-days`, default 7); within a season, words are ordered early → late
by sub-season and spread across the days. It aims for *sensible + reviewable*,
not perfect — the reviewer has the final say.

### Descriptions (stage 3) — needs an LLM

Emit prompt batches (one self-contained `.txt` per batch, ready to paste into
any model; plus a `.jsonl` for programmatic drivers):

```bash
python3 scripts/content/fill/describe.py emit \
    --spine scripts/content/fill/spine-2026.csv \
    --out-dir scripts/content/fill/batches --batch-size 20
```

Run each `batches/batch-*.txt` through an LLM and save each JSON-array reply as
`scripts/content/fill/responses/batch-XXX.json`. To do the whole year turnkey
with Claude instead of pasting by hand:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
python3 scripts/content/fill/describe_via_claude.py \
    --batches scripts/content/fill/batches \
    --responses scripts/content/fill/responses
```

Then ingest + validate (rejects empty prose or a leftover `(YYYY-MM-DD)` stamp):

```bash
python3 scripts/content/fill/describe.py ingest \
    --responses scripts/content/fill/responses \
    --out scripts/content/fill/descriptions.csv
```

**A Japanese reviewer should read `descriptions.csv` before assembly.** The
prompt text — the workflow's LLM contract — lives in `describe.py`
(`PROMPT_PREAMBLE`); edit it there.

### Merge + gate (stage 5)

```bash
python3 scripts/content/fill/build_csv.py \
    --spine        scripts/content/fill/spine-2026.csv \
    --descriptions scripts/content/fill/descriptions.csv \
    --out          content/kigo-2026.csv

# the real validation — the same gate CI/regeneration uses:
python3 scripts/content/assemble.py --csv content/kigo-2026.csv --out Resources/manifest.json
```

`build_csv.py` only emits dates present in **both** inputs, so a partial run
yields a smaller but fully valid CSV — no blank cells. It drops every helper
column, writing exactly the **7-column** contract (`date, kanji, reading_ja,
reading_en, translation_en, description_ja, description_en`) `csv_parser.py`
expects.

## Worked sample in this repo

`content/kigo-2026.sample.csv` is a real-spine, LLM-authored-prose sample
produced by this workflow that **passes `assemble.py`**. It proves the
pipeline end-to-end; extend to the full year by running `generate`/descriptions
for all 365 dates.

## Image sourcing was retired

Per-day image sourcing (Pexels/Pixabay candidates, the Japanese Wikipedia
lead-image lookup, the review UI's candidate gallery, `--image-base-url`) was
removed by ADR 0026: the app now ships 24 uniform, bundled, per-Sekki
backdrops instead of a verified photograph per day, which made per-day image
review unnecessary. See ADR 0026
(`docs/adr/0026-uniform-per-sekki-bundled-backdrops.md`) for the decision and
its consequences for this tool.
