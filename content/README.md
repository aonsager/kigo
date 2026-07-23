# Kigo content pipeline

`Resources/manifest.json` — the Daily Map content the app bundles — is
**always regenerated from a reviewed source CSV, never hand-edited** (ADR
0022). This document is the content editor's guide: the CSV format, the
regeneration command, and how to draft the remaining rows with an LLM.

The CSV contract is **text-only**: the app ships 24 bundled per-Sekki
backdrop images (ADR 0026) instead of a sourced photograph per day, so
neither this pipeline nor its CSV contract carries any image or attribution
column — see "Images" below.

The pipeline lives in `scripts/content/` (pure Python, stdlib only, no
network, no third-party dependencies):

- `csv_parser.py` — reads the CSV, enforces the column contract below.
- `validator.py` — the pre-write gate (see "The validator gate" below).
- `assembler.py` — builds the manifest dict from parsed rows + the existing
  Kō/Sekki content, and writes it out.
- `assemble.py` — the CLI entrypoint that ties the above together.
- `test_pipeline.py` — the pipeline's own test suite (`python3
  scripts/content/test_pipeline.py`).
- `fixtures/` — committed malformed-row CSVs used by the test suite to prove
  the validator gate actually refuses bad input.

`content/kigo-2026.example.csv` is the worked example: ≥8 real, fully
localized rows that double as the test gate's fixture and as the template a
human extends into the full 365-row year.

## CSV column contract

One row per 2026 date. Every column below is **required and must be
non-empty** for every row — `csv_parser.py` rejects the whole run (nonzero
exit, no output written) if any is missing or blank:

| Column | Meaning |
|---|---|
| `date` | `YYYY-MM-DD`, the Daily Map key this row fills |
| `kanji` | The kigo's word, in kanji |
| `reading_ja` | Hiragana reading of the kigo |
| `reading_en` | Romaji reading (the English-side "reading") |
| `translation_en` | Concise English translation/name of the kigo (e.g. "cherry-blossom viewing") — the free-Encounter English label shown beside the word (ADR 0024). English-only, a noun phrase, no trailing period |
| `description_ja` | 1–2 sentence Japanese description, present tense, no leftover `(YYYY-MM-DD)` date-stamp text |
| `description_en` | English description, written natively for an English reader (not a literal translation), same constraints |

This is the full contract — 7 columns, no image or attribution fields (see
"Images" below).

## Regenerating the manifest

One command, run from the repo root, reads the reviewed CSV and the existing
bundled manifest (for its Kō/Sekki content) and writes a complete manifest to
`--out`:

```bash
python3 scripts/content/assemble.py --csv content/kigo-2026.csv --out Resources/manifest.json
```

(Substitute `content/kigo-2026.example.csv` to try the worked example, and
any scratch path for `--out` to inspect the result before overwriting the
bundled manifest.) The command is deterministic and idempotent — running it
twice against the same CSV produces byte-identical output — and it never
modifies the source CSV or the `--manifest` input, only `--out`.

### The validator gate

Before anything is written, every assembled row is checked for:

- full bilingual completeness — `reading` and `description` each need both
  `ja` and `en`;
- a non-empty `kanji` and `translationEn`;
- no leftover `(YYYY-MM-DD)` date-stamp instrumentation in the description
  (a holdover from the old dummy-data Daily Map that must never survive into
  real content).

If **any** row fails **any** of these checks, `assemble.py` exits nonzero,
prints the failing row(s) and reason(s) to stderr, and writes **nothing** —
whatever previously existed at `--out` is left completely untouched. Fix the
CSV and re-run; there is no partial-write state to clean up.

## LLM-fill workflow

Filling the remaining year's rows (the worked example only covers ~8–12) is
a human-run, LLM-assisted drafting pass, not something the pipeline
automates end-to-end — readings and seasonal placement need a human review
gate (ADR 0022).

1. **Spine first.** Before drafting prose, nail down `date`, `kanji`,
   `reading_ja`, `reading_en` for every remaining day from an authoritative
   saijiki source (e.g. a kigo almanac/WKD-style list). Get this column set
   right before generating descriptions — everything else is drafted against
   it.
2. **Draft descriptions with an LLM, one batch at a time.** For each row (or
   a small batch), prompt with the row's `kanji`, `reading_ja`, and season,
   and ask for:
   - `description_ja` — a calm, 1–2 sentence Japanese gloss, present tense,
     sensory, no haiku clichés;
   - `description_en` — an English description written natively for an
     English reader (not a translation of the Japanese), same voice.
   Paste the drafts directly into the CSV's `description_ja`/`description_en`
   columns for that row.
3. **Never let the LLM invent a date-stamp.** Drafted prose must not contain
   anything resembling `(2026-03-21)` — that pattern is reserved for the old
   dummy-data instrumentation and is explicitly rejected by the validator
   gate (see above). If a draft has one (e.g. copied from an old example),
   strip it before saving.
4. **Human review, in the CSV.** A Japanese-literate reviewer reads the CSV
   top to bottom, correcting readings and descriptions inline. This is the
   one step that stays manual — the pipeline's job is to make it the
   *only* manual step, and to refuse (loudly, before writing anything) if a
   row still needs work.
5. **Assemble and check.** Run the regeneration command above; a nonzero
   exit means at least one row still needs fixing — the error message names
   the row and the missing/invalid field. A zero exit means the manifest is
   ready to review at `--out` before it replaces the bundled one.

## Images

There is no per-day image step. ADR 0022 originally delivered a sourced
photograph per day by remote URL + on-device cache (`image_id` +
`imageBaseURL` columns, per-image attribution); ADR 0026 superseded that
image-delivery half and pivoted to 24 uniform, bundled, per-Sekki backdrop
images shipped in the app binary, resolved purely from the current Sekki —
no per-day data, no fetch, no attribution. The CSV contract, the validator
gate, and `scripts/content/fill/` (see its README) were all updated
accordingly to carry no image or attribution fields. See ADR 0026
(`docs/adr/0026-uniform-per-sekki-bundled-backdrops.md`) for the full
rationale and consequences.
