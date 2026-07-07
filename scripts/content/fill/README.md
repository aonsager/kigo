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
   emit ▶ LLM ▶ ingest                        Pexels+Pixabay, Japanese-first (or --placeholder)
        │                                             │
        ▼                                             ▼
   descriptions.csv                              images.csv
             └───────────────────┬───────────────────┘
                     (5) build_csv.py  ── join on date ──▶ content/kigo-2026.csv
                                 │
                     scripts/content/assemble.py  ── the real gate ──▶ manifest.json
```

## The wrapper (recommended) — `fill.py` + web review

`fill.py` orchestrates the stages below over a SQLite review store
(`review.db`, gitignored) and a local web review UI. See ADR 0025.

```bash
# 1. seed the 365 day facts (deterministic; consumes spine_pool.json)
python3 scripts/content/fill/fill.py spine

# 2. generate prose + image candidates for a date range (unapproved days only;
#    needs ANTHROPIC_API_KEY + a provider key, or --no-images / --no-descriptions)
python3 scripts/content/fill/fill.py generate --from 2026-03-01 --to 2026-03-31

# 3. review in the browser: edit readings/prose, pick an image, approve each day
python3 scripts/content/fill/fill.py review        # http://127.0.0.1:8000

# 4. compile approved days → content/kigo-2026.csv → manifest (the assemble gate)
python3 scripts/content/fill/fill.py compile --image-base-url https://cdn.example/kigo
```

"Approved freezes": `spine`/`generate` never touch an approved day (use `--force`
to override). `compile` exports only approved days (partial manifest), reporting
skipped ones. The per-stage scripts below remain for ad-hoc use.

## What you must supply

| Input | For | How |
|---|---|---|
| **An LLM** (stage 3) | authoring `description_ja` / `description_en` | any capable chat model, or `ANTHROPIC_API_KEY` + `describe_via_claude.py` |
| **Pillow** (stage 4) | image smart-cropping + JPEG encoding | `python3 -m pip install Pillow` |
| **An image-provider API key** (stage 4) | real photography + attribution | free from [Pixabay](https://pixabay.com/api/docs/) or [Pexels](https://www.pexels.com/api/); put `PIXABAY_API_KEY` / `PEXELS_API_KEY` in a gitignored `scripts/content/fill/.env` |
| **A static image host** (post-workflow) | re-hosting chosen JPEGs at a stable base URL | Cloudflare R2 / S3 / GitHub release; becomes `--image-base-url` for `assemble.py` |
| **A Japanese-literate reviewer** | the human gate on `spine-2026.csv` + descriptions | read top-to-bottom, correct inline |

Everything else runs offline with the Python stdlib — Pillow is the only third-party dependency.

## Legal posture (why we don't ship the source's English)

The spine comes from [`brokyo/saijikijs`](https://github.com/brokyo/saijikijs)
(pinned commit `7ca6de5`), an aggregation of two **copyrighted** English
translations (Higginson/Kondo's *500 Essential Season Words* and UVA's *Nyūmon
Saijiki*) re-declared under The Unlicense — a declaration that cannot validly
clear the upstream translators' rights. So `fetch_spine.py` harvests **only the
uncopyrightable traditional facts** — kanji, kana + romaji readings, season,
sub-season, category — plus a short English *name* (`gloss_en`), a factual
label rather than descriptive prose. It is used as a search helper (kanji-first,
falling back to `gloss_en`, across both Pexels and Pixabay) and is also written
to the manifest as the image's short attribution title (`attribution_title_en`)
— it is never shipped as descriptive prose. All shipped prose is our own
(stage 3). Images are Pexels- or Pixabay-licensed with photographer credit.

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

### Images (stage 4) — two-phase human-in-the-loop

Stage 4 is two-phase, human-in-the-loop (like `describe.py`'s emit/ingest).
It needs **Pillow** (the workflow's only non-stdlib dependency, used just here):

```bash
python3 -m pip install Pillow
```

Providers: **pexels** (primary) and **pixabay** (fallback), both free and
commercial-use; keys in the gitignored `scripts/content/fill/.env`
(`PEXELS_API_KEY` / `PIXABAY_API_KEY`). Each day is searched **Japanese-first**
(the kanji, then the English `gloss_en`, then romaji) across both providers, and
the **3** candidates are drawn **round-robin, one per search rung** — so you
typically get a Pexels kanji match, a Pexels English-gloss match, and a Pixabay
match, rather than three near-duplicates from one query. (This matters because
Pexels never returns *empty* — it substitutes popular photos for an unmatched
Japanese term — so spreading across rungs is what surfaces the English-gloss and
Pixabay results a human can compare.) Each candidate must clear a min-resolution
floor, and is smart-cropped to the phone screen ratio (9:19.5), downscaled, and
JPEG-encoded — so you review the *actual* image that would ship.

Alongside the stock candidates, each day also gets the **Japanese Wikipedia lead
image** (looked up by kanji, then by the English `gloss_en` on English
Wikipedia) as a licensed **4th candidate and accuracy reference**. Its real
license is read from Wikimedia; it is marked **`usable`** in `candidates.csv`
only when that license permits shipping (public-domain / CC0 / CC-BY / CC-BY-SA)
and it clears the resolution floor — otherwise it is kept **reference-only** so
you can still check whether the stock picks show the right subject, but `select`
will refuse to ship it. Disable with `--no-wikipedia`.

```bash
# keyless placeholders, to build + gate the CSV before you have a key:
python3 scripts/content/fill/fetch_images.py fetch \
    --spine scripts/content/fill/spine-2026.csv \
    --out scripts/content/fill/images.csv --placeholder

# real: acquire + process 3 candidates per day
python3 scripts/content/fill/fetch_images.py fetch \
    --spine scripts/content/fill/spine-2026.csv \
    --candidates-out scripts/content/fill/candidates.csv \
    --out-images scripts/content/fill/downloads
```

Then **review**: open `candidates.csv`, look at the matching
`downloads/<image_id>__c1..c3.jpg`, and put any mark (e.g. `x`) in the `chosen`
column of the winner — exactly one per date. Resolve the choice:

```bash
python3 scripts/content/fill/fetch_images.py select \
    --candidates-in scripts/content/fill/candidates.csv \
    --out scripts/content/fill/images.csv \
    --out-images scripts/content/fill/downloads
```

`select` validates one `chosen` per date, copies each winner to the canonical
`<image_id>.jpg`, and writes the 8-column `images.csv` `build_csv.py` expects.
Days with no candidate are reported on stderr — refine the query and rerun.
Tuning flags: `--candidates`, `--per-page`, `--min-width/--min-height`,
`--aspect`, `--max-edge`, `--jpeg-quality`, `--no-japanese`, `--no-fallback`.

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
