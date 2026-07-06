#!/usr/bin/env python3
"""describe.py — STAGE 3 of the kigo-2026 fill workflow.

Turns the factual spine (stage 2) into the two prose columns the manifest
needs — `description_ja` and `description_en` — via an LLM, WITHOUT locking the
workflow to any one provider. It has two subcommands:

    emit    Write ready-to-run LLM prompt batches from the spine CSV. Each
            batch is a self-contained .txt you can paste into any capable
            chat model (Claude, etc.), plus a machine-readable .jsonl of the
            rows in that batch for programmatic drivers.

    ingest  Read the LLM's JSON responses back, validate them (both languages
            present, no forbidden date-stamp, non-empty), and write a
            descriptions.csv keyed by date for stage 5 (build_csv.py).

Why prose is LLM-authored and human-reviewed, not scraped: the reputable
source's own English glosses are copyrighted (see fetch_spine.py / README);
ADR 0022 makes authored-then-reviewed descriptions the one deliberately manual
step. This script makes that step batchable and provider-agnostic; the human
review still happens on descriptions.csv (or the CSV) before assembly.

Stdlib only. Usage (from repo root):

    # 1. emit prompt batches (optionally only for a subset of dates)
    python3 scripts/content/fill/describe.py emit \
        --spine scripts/content/fill/spine-2026.csv \
        --out-dir scripts/content/fill/batches \
        --batch-size 20

    # 2. run each batches/batch-*.txt through an LLM, save each JSON reply as
    #    scripts/content/fill/responses/batch-XXX.json (a JSON array)

    # 3. ingest the replies
    python3 scripts/content/fill/describe.py ingest \
        --responses scripts/content/fill/responses \
        --out scripts/content/fill/descriptions.csv
"""
import argparse
import csv
import json
import re
import sys
from pathlib import Path

DATE_STAMP_RE = re.compile(r"\(\d{4}-\d{2}-\d{2}\)")  # mirrors validator.py's forbidden stamp
DESCRIPTION_COLUMNS = ("date", "translation_en", "description_ja", "description_en")

# --- The prompt. This IS the workflow's LLM contract; edit it here. ----------
PROMPT_PREAMBLE = """\
You are writing calm, original, EXPLANATORY entries for a Japanese seasonal-word
(kigo, 季語) wellness app. Each entry is shown beside a real photograph, so it
must describe what the word actually MEANS — not paint an imaginary scene that
might clash with the picture. For each kigo below, write a short English name
and TWO short descriptions:

- translation_en: a concise English translation/name of the word itself (a
  noun phrase, not a sentence), e.g. 花見 → "cherry-blossom viewing", 初鰹 →
  "the first bonito of summer". Lowercase except for proper nouns; no trailing
  period. This is the English reader's equivalent of reading the kanji, shown
  free beside the word — keep it a clean label, not a definition.
- description_ja: 1–2 sentences of natural, present-tense Japanese that explain
  what the word denotes (the thing, custom, plant, creature, or phenomenon) AND
  why it belongs to this season — its seasonal or historical/cultural
  significance. Informative and quietly evocative, like a good almanac gloss;
  not a poem or an invented moment.
- description_en: 1–2 sentences written NATIVELY for an English reader (NOT a
  translation of the Japanese), same explanatory purpose — say what it is and
  what makes it a marker of this season, so a non-Japanese reader understands
  the word and its place in the year.

Voice rules:
- EXPLAIN, don't stage a scene. Prefer "X is …, traditionally associated with …"
  over "you hear/see/feel …". Do NOT use second person ("you"), and do NOT
  narrate a single specific imagined moment.
- Ground it in what the word really refers to and its actual seasonal/cultural
  role; if there is well-known historical background, include it briefly.
- Calm and plain; no haiku, no quoted poems, no purple prose, no clichéd
  openers repeated across entries ("風物詩", "訪れを告げる").

Hard rules:
- Write ORIGINAL prose. Do NOT reproduce any existing dictionary/saijiki gloss.
- NEVER include a date stamp like "(2026-03-21)" anywhere — it is rejected by
  the pipeline's validator.
- Keep each description to 1–2 sentences. No markdown, no leading labels.
- Use the kanji/reading/season/category given as your factual anchor; do not
  invent false facts.

Return ONLY a JSON array, one object per input row, in the SAME ORDER:
[{"date": "...", "translation_en": "...", "description_ja": "...", "description_en": "..."}, ...]

Input rows:
"""


def _read_spine(path, dates=None):
    rows = list(csv.DictReader(path.open(encoding="utf-8")))
    if dates:
        wanted = set(dates)
        rows = [r for r in rows if r["date"] in wanted]
    return rows


def _batch_payload(rows):
    """The compact per-row fact object the model sees."""
    return [
        {
            "date": r["date"],
            "kanji": r["kanji"],
            "reading_ja": r["reading_ja"],
            "reading_en": r["reading_en"],
            "season": r["season"],
            "subseason": r["subseason"],
            "category": r["category"],
            # a rough source name to seed (not copy) translation_en; may be blank
            "name_hint_en": r.get("gloss_en", ""),
        }
        for r in rows
    ]


def cmd_emit(args):
    rows = _read_spine(args.spine, args.dates.split(",") if args.dates else None)
    if not rows:
        print("error: no spine rows selected", file=sys.stderr)
        return 1
    args.out_dir.mkdir(parents=True, exist_ok=True)

    n = 0
    for i in range(0, len(rows), args.batch_size):
        batch = rows[i : i + args.batch_size]
        idx = i // args.batch_size
        payload = _batch_payload(batch)
        prompt = PROMPT_PREAMBLE + json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
        (args.out_dir / f"batch-{idx:03d}.txt").write_text(prompt, encoding="utf-8")
        (args.out_dir / f"batch-{idx:03d}.jsonl").write_text(
            "\n".join(json.dumps(p, ensure_ascii=False) for p in payload) + "\n", encoding="utf-8"
        )
        n += 1
    print(f"wrote {n} batch prompt(s) covering {len(rows)} rows to {args.out_dir}")
    print(f"  run each batch-*.txt through an LLM; save replies as {args.responses_hint}")
    return 0


def _load_responses(responses_dir):
    """Flatten every batch reply (a JSON array) into date -> {ja, en}."""
    merged = {}
    files = sorted(Path(responses_dir).glob("*.json"))
    if not files:
        raise SystemExit(f"error: no *.json response files in {responses_dir}")
    for f in files:
        data = json.loads(f.read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise SystemExit(f"error: {f} is not a JSON array")
        for obj in data:
            merged[obj["date"]] = {
                "translation_en": (obj.get("translation_en") or "").strip(),
                "ja": (obj.get("description_ja") or "").strip(),
                "en": (obj.get("description_en") or "").strip(),
            }
    return merged


def cmd_ingest(args):
    merged = _load_responses(args.responses)
    errors = []
    out_rows = []
    for date in sorted(merged):
        translation_en = merged[date]["translation_en"]
        ja, en = merged[date]["ja"], merged[date]["en"]
        if not translation_en:
            errors.append(f"{date}: translation_en empty")
        if not ja:
            errors.append(f"{date}: description_ja empty")
        if not en:
            errors.append(f"{date}: description_en empty")
        if DATE_STAMP_RE.search(ja + en):
            errors.append(f"{date}: description contains a forbidden (YYYY-MM-DD) date stamp")
        out_rows.append(
            {"date": date, "translation_en": translation_en, "description_ja": ja, "description_en": en}
        )

    if errors:
        print("error: description responses failed validation:", file=sys.stderr)
        for e in errors:
            print("  " + e, file=sys.stderr)
        return 1

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=DESCRIPTION_COLUMNS)
        writer.writeheader()
        writer.writerows(out_rows)
    print(f"wrote {len(out_rows)} descriptions to {args.out}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_emit = sub.add_parser("emit", help="write LLM prompt batches from the spine CSV")
    p_emit.add_argument("--spine", required=True, type=Path)
    p_emit.add_argument("--out-dir", required=True, type=Path)
    p_emit.add_argument("--batch-size", type=int, default=20)
    p_emit.add_argument("--dates", help="optional comma-separated subset of dates to emit")
    p_emit.add_argument("--responses-hint", default="scripts/content/fill/responses/batch-XXX.json",
                        help=argparse.SUPPRESS)
    p_emit.set_defaults(func=cmd_emit)

    p_ing = sub.add_parser("ingest", help="merge + validate LLM JSON replies into descriptions.csv")
    p_ing.add_argument("--responses", required=True, type=Path, help="dir of *.json reply arrays")
    p_ing.add_argument("--out", required=True, type=Path)
    p_ing.set_defaults(func=cmd_ingest)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
