# kigo-2026 fill workflow

Fills `content/kigo-2026.csv` — the reviewable source CSV the deterministic
`scripts/content/assemble.py` pipeline turns into `Resources/manifest.json`
(ADR 0022) — with real, sourced content for all 365 days of 2026.

This is the concrete implementation of the "LLM-fill workflow" sketched in
`content/README.md`. It splits the job into small, reviewable stages so the one
step that *must* stay human (reading the Japanese) is the only manual gate.

```
                 brokyo/saijikijs kigo.json @ pinned SHA
                                 │
        (1) fetch_spine.py  ── factual fields only ──▶ spine_pool.json
                                 │
        (2) assign_dates.py ── 365-day placement ────▶ spine-2026.csv  ◀── human review
                                 │
             ┌───────────────────┴───────────────────┐
   (3) describe.py                            (4) fetch_images.py
   emit ▶ LLM ▶ ingest                        Pexels API (or --placeholder)
        │                                             │
        ▼                                             ▼
   descriptions.csv                              images.csv
             └───────────────────┬───────────────────┘
                     (5) build_csv.py  ── join on date ──▶ content/kigo-2026.csv
                                 │
                     scripts/content/assemble.py  ── the real gate ──▶ manifest.json
```

## What you must supply

| Input | For | How |
|---|---|---|
| **An LLM** (stage 3) | authoring `description_ja` / `description_en` | any capable chat model, or `ANTHROPIC_API_KEY` + `describe_via_claude.py` |
| **A Pexels API key** (stage 4) | real photography + attribution | free at <https://www.pexels.com/api/>; export `PEXELS_API_KEY` |
| **A static image host** (post-workflow) | re-hosting chosen JPEGs at a stable base URL | Cloudflare R2 / S3 / GitHub release; becomes `--image-base-url` for `assemble.py` |
| **A Japanese-literate reviewer** | the human gate on `spine-2026.csv` + descriptions | read top-to-bottom, correct inline |

Everything else runs offline with the Python stdlib — no third-party packages.

## Legal posture (why we don't ship the source's English)

The spine comes from [`brokyo/saijikijs`](https://github.com/brokyo/saijikijs)
(pinned commit `7ca6de5`), an aggregation of two **copyrighted** English
translations (Higginson/Kondo's *500 Essential Season Words* and UVA's *Nyūmon
Saijiki*) re-declared under The Unlicense — a declaration that cannot validly
clear the upstream translators' rights. So `fetch_spine.py` harvests **only the
uncopyrightable traditional facts** — kanji, kana + romaji readings, season,
sub-season, category — plus a short English *name* (`gloss_en`) used **solely**
as a Pexels search term and **never written to the manifest**. All shipped prose
is our own (stage 3). Images are Pexels-licensed with photographer credit.

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

### Images (stage 4) — needs a Pexels key (or run keyless first)

```bash
# keyless placeholders, so you can build + gate the CSV before you have a key:
python3 scripts/content/fill/fetch_images.py \
    --spine scripts/content/fill/spine-2026.csv \
    --out scripts/content/fill/images.csv --placeholder

# real: query Pexels per row, record attribution, download the JPEGs to re-host:
export PEXELS_API_KEY=...
python3 scripts/content/fill/fetch_images.py \
    --spine scripts/content/fill/spine-2026.csv \
    --out scripts/content/fill/images.csv \
    --api-key "$PEXELS_API_KEY" \
    --download scripts/content/fill/downloads
```

The auto-picked top result is a *candidate* — image curation is a human step
(ADR 0022). Rows with no Pexels match are written as placeholders and listed on
stderr so you can refine the query and rerun. Pexels free tier is 200 req/hour;
`--sleep` throttles and 429s back off, so a full 365-row run self-paces.

After you re-host the downloaded (and optimized) images, pass their base URL to
`assemble.py` as `--image-base-url https://your-host/path`.

### Merge + gate (stage 5)

```bash
python3 scripts/content/fill/build_csv.py \
    --spine        scripts/content/fill/spine-2026.csv \
    --descriptions scripts/content/fill/descriptions.csv \
    --images       scripts/content/fill/images.csv \
    --out          content/kigo-2026.csv

# the real validation — the same gate CI/regeneration uses:
python3 scripts/content/assemble.py --csv content/kigo-2026.csv --out Resources/manifest.json
```

`build_csv.py` only emits dates present in **all three** inputs, so a partial
run yields a smaller but fully valid CSV — no blank cells. It drops every helper
column, writing exactly the 13-column contract `csv_parser.py` expects.

## Worked sample in this repo

`content/kigo-2026.sample.csv` is a 15-date, all-seasons sample produced by this
exact workflow (real spine + LLM-authored bilingual descriptions + *placeholder*
images) that **passes `assemble.py`**. It proves the pipeline end-to-end; extend
to the full year by running descriptions for all 365 dates and swapping in real
Pexels images.
