# Content-fill Tool → Text-Only Editorial — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Descope `scripts/content/fill/` to a text-only editorial Kigo-review tool — strip all image sourcing, repair the 7-column contract boundary, and migrate the existing `review.db` preserving every `days` row.

**Architecture:** The four-verb CLI (`spine` → `generate` → `review` → `compile`) over a SQLite store stays; every image concern is removed. `store.py` sheds the `candidates` table + `chosen_candidate_id` (via an automatic, version-guarded migration) and re-gates export on prose completeness instead of a chosen image. `webapp.py`/`web/` become a text-only editor. `fill.py` generates prose only and compiles to the 7-column contract. `fetch_images.py` and the candidate machinery are deleted.

**Tech Stack:** Python 3 stdlib (+ `sqlite3`), a vanilla-JS SPA over `http.server`. No app/Swift/simulator involvement.

## Global Constraints

- **Run tests with the repo convention:** each suite is a directly-runnable script — `python3 scripts/content/fill/<name>.py` prints `ALL PASS` (or a standard unittest summary) on success. The four suites: `test_store.py`, `test_fill.py`, `test_webapp.py` (kept), `test_fetch_images.py` (deleted in Task 6).
- **The 7-column contract is fixed and must match `scripts/content/csv_parser.REQUIRED_COLUMNS` exactly, in order:** `date, kanji, reading_ja, reading_en, translation_en, description_ja, description_en`.
- **Prose-completeness gate = what `scripts/content/validator.py` requires of a valid entry:** non-empty `kanji`, `reading_ja`, `reading_en`, `translation_en`, `description_ja`, `description_en` (validator requires `translationEn` and both `reading.{ja,en}` / `description.{ja,en}`). A day that would pass `assemble.py` is exportable; one that would fail is skipped. Images are not part of the gate.
- **Preserve `review.db`:** the migration keeps every `days` row (facts, prose, `approved`) and drops only the `candidates` table + `chosen_candidate_id` column. It is idempotent and runs automatically on store open, guarded by `PRAGMA user_version`.
- **`compile` stays replace-not-merge:** `assemble.py` rebuilds the whole `dailyMap` from the exported rows (unchanged pre-existing behavior). Do not touch `assemble.py`/`csv_parser.py`/`validator.py`.
- **No revival of image sourcing.** After this work, `grep -rn 'fetch_images\|image_id\|attribution\|chosen_candidate_id\|candidates\|--image-base-url' scripts/content/fill/` returns no live-code hits (comments/README history aside, which Task 7 also cleans).
- Local runtime is SQLite 3.51 (`ALTER TABLE ... DROP COLUMN` supported); the migration still carries a rebuild fallback for < 3.35.

---

### Task 1: `build_csv.py` → 7-column contract

Reduce the contract to the 7 text columns and make the ad-hoc join a spine+descriptions merge (no images input). `build_csv.CONTRACT_COLUMNS` is the single source of truth consumed by `store.export_rows` and `fill.write_contract_csv`.

**Files:**
- Modify: `scripts/content/fill/build_csv.py`

**Interfaces:**
- Produces: `build_csv.CONTRACT_COLUMNS = ("date","kanji","reading_ja","reading_en","translation_en","description_ja","description_en")`; `main(argv)` takes `--spine --descriptions --out` (no `--images`).

- [ ] **Step 1: Rewrite `CONTRACT_COLUMNS` and `main`**

```python
#!/usr/bin/env python3
"""build_csv.py — STAGE 5 (merge) of the kigo-2026 fill workflow.

Joins the two reviewable intermediates —

    spine-2026.csv    (stage 2: date, kanji, readings, + season helpers)
    descriptions.csv  (stage 3: date, translation_en, description_ja, description_en)

— on `date` and writes the final source CSV in the exact 7-column contract that
scripts/content/assemble.py consumes (helper columns like season / subseason /
category / gloss_en are DROPPED here, so they never reach the manifest). Only
dates present in BOTH inputs are emitted, so a partial run yields a smaller but
fully valid CSV rather than blank cells.

After writing, run the real gate to prove it:

    python3 scripts/content/assemble.py --csv content/kigo-2026.csv --out /tmp/manifest.json

Stdlib only. Usage (from repo root):
    python3 scripts/content/fill/build_csv.py \
        --spine        scripts/content/fill/spine-2026.csv \
        --descriptions scripts/content/fill/descriptions.csv \
        --out          content/kigo-2026.csv
"""
import argparse
import csv
import sys
from pathlib import Path

# Must match scripts/content/csv_parser.REQUIRED_COLUMNS exactly (order included).
CONTRACT_COLUMNS = (
    "date", "kanji", "reading_ja", "reading_en", "translation_en",
    "description_ja", "description_en",
)


def _by_date(path):
    return {r["date"]: r for r in csv.DictReader(path.open(encoding="utf-8"))}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--spine", required=True, type=Path)
    parser.add_argument("--descriptions", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args(argv)

    spine = _by_date(args.spine)
    descriptions = _by_date(args.descriptions)

    complete = sorted(set(spine) & set(descriptions))
    if not complete:
        print("error: no dates present in both inputs", file=sys.stderr)
        return 1

    out_rows = []
    for date in complete:
        s, d = spine[date], descriptions[date]
        out_rows.append({
            "date": date,
            "kanji": s["kanji"],
            "reading_ja": s["reading_ja"],
            "reading_en": s["reading_en"],
            "translation_en": d["translation_en"],
            "description_ja": d["description_ja"],
            "description_en": d["description_en"],
        })

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CONTRACT_COLUMNS)
        writer.writeheader()
        writer.writerows(out_rows)

    total = len(spine)
    print(f"wrote {len(out_rows)}/{total} complete rows to {args.out}")
    if len(out_rows) < total:
        missing_desc = len(set(spine) - set(descriptions))
        print(f"  ({missing_desc} dates still need descriptions)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Verify import + join on a tiny fixture**

Run:
```bash
cd /Users/aonsager/projects/kigo
python3 - <<'PY'
import csv, tempfile, pathlib, importlib.util, sys
sys.path.insert(0, "scripts/content/fill")
import build_csv
assert build_csv.CONTRACT_COLUMNS == ("date","kanji","reading_ja","reading_en","translation_en","description_ja","description_en"), build_csv.CONTRACT_COLUMNS
d = pathlib.Path(tempfile.mkdtemp())
(d/"spine.csv").write_text("date,kanji,reading_ja,reading_en\n2026-01-01,鏡餅,かがみもち,kagami-mochi\n", encoding="utf-8")
(d/"desc.csv").write_text("date,translation_en,description_ja,description_en\n2026-01-01,mirror mochi,和文,English\n", encoding="utf-8")
rc = build_csv.main(["--spine", str(d/"spine.csv"), "--descriptions", str(d/"desc.csv"), "--out", str(d/"out.csv")])
assert rc == 0
rows = list(csv.DictReader((d/"out.csv").open(encoding="utf-8")))
assert list(rows[0].keys()) == list(build_csv.CONTRACT_COLUMNS), rows[0].keys()
assert "image_id" not in rows[0]
print("BUILD_CSV OK")
PY
```
Expected: `BUILD_CSV OK`.

- [ ] **Step 3: Commit**

```bash
git add scripts/content/fill/build_csv.py
git commit -m "feat(fill): build_csv 7-column contract (drop image columns)"
```

---

### Task 2: `store.py` → text-only schema, migration, prose-gated export

Drop the `candidates` table and `chosen_candidate_id`, add an automatic version-guarded migration that preserves every `days` row, delete the candidate functions, and re-gate `export_rows` on prose completeness.

**Files:**
- Modify: `scripts/content/fill/store.py`
- Test: `scripts/content/fill/test_store.py`

**Interfaces:**
- Consumes: `build_csv.CONTRACT_COLUMNS` (Task 1).
- Produces: `store.connect(path)` (runs migration); `store.export_rows(conn, date_from, date_to)` → list of dicts keyed exactly by `CONTRACT_COLUMNS`; `store.pending_dates(...)`. REMOVED: `add_candidate`, `get_candidates`, `clear_candidates`, `set_chosen`, `_contract_row`, `CANDIDATE_STORE_COLUMNS`.

- [ ] **Step 1: Write the migration + export tests first (RED)**

Add to `scripts/content/fill/test_store.py` (and DELETE the four image cases: `test_add_and_get_candidates`, `test_set_chosen_validates_ownership_and_usable`, `test_clear_candidates_resets_chosen`, `test_export_rows_only_approved_with_chosen`):

```python
def test_migration_drops_candidates_and_preserves_days(tmp_path):
    # Build a pre-migration (v0) DB by hand: old days schema with
    # chosen_candidate_id + a candidates table + real editorial data.
    import sqlite3
    p = tmp_path / "old.db"
    c = sqlite3.connect(p)
    c.executescript("""
        CREATE TABLE days (date TEXT PRIMARY KEY, kanji TEXT DEFAULT '',
            reading_ja TEXT DEFAULT '', reading_en TEXT DEFAULT '',
            season TEXT DEFAULT '', subseason TEXT DEFAULT '', category TEXT DEFAULT '',
            gloss_en TEXT DEFAULT '', translation_en TEXT DEFAULT '',
            description_ja TEXT DEFAULT '', description_en TEXT DEFAULT '',
            chosen_candidate_id INTEGER, approved INTEGER DEFAULT 0,
            created_at TEXT DEFAULT '', updated_at TEXT DEFAULT '');
        CREATE TABLE candidates (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, out_file TEXT);
        INSERT INTO days (date, kanji, description_ja, approved, chosen_candidate_id)
            VALUES ('2026-03-03', '雛祭', '和文の説明', 1, 7);
    """)
    c.execute("PRAGMA user_version = 0")
    c.commit(); c.close()

    conn = store.connect(p)  # triggers migration
    cols = {r[1] for r in conn.execute("PRAGMA table_info(days)")}
    assert "chosen_candidate_id" not in cols
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert "candidates" not in tables
    assert conn.execute("PRAGMA user_version").fetchone()[0] == store._SCHEMA_VERSION
    day = store.get_day(conn, "2026-03-03")
    assert day["kanji"] == "雛祭" and day["description_ja"] == "和文の説明" and day["approved"] == 1
    # Idempotent: re-opening does not error or change data.
    conn2 = store.connect(p)
    assert store.get_day(conn2, "2026-03-03")["kanji"] == "雛祭"


def test_export_rows_gates_on_prose_completeness(tmp_path):
    conn = store.connect(tmp_path / "r.db")
    store.seed_days(conn, [{"date": "2026-05-05", "kanji": "菖蒲", "reading_ja": "しょうぶ",
                            "reading_en": "shoubu"}])
    # Not approved → not exported.
    assert store.export_rows(conn) == []
    store.set_day_fields(conn, "2026-05-05", translation_en="iris",
                         description_ja="和文", description_en="English")
    store.set_approved(conn, "2026-05-05", True)
    rows = store.export_rows(conn)
    assert len(rows) == 1
    assert list(rows[0].keys()) == list(build_csv.CONTRACT_COLUMNS)
    assert rows[0]["kanji"] == "菖蒲"
    # Approved but incomplete (blank description_en) → skipped.
    store.set_day_fields(conn, "2026-05-05", description_en="")
    assert store.export_rows(conn) == []
```

(Ensure `import build_csv` is present at the top of `test_store.py`.)

- [ ] **Step 2: Run to verify it fails**

Run: `python3 scripts/content/fill/test_store.py`
Expected: FAIL — `AttributeError: module 'store' has no attribute '_SCHEMA_VERSION'` (and the migration/export behavior not yet implemented).

- [ ] **Step 3: Rewrite `store.py`**

Replace the imports/schema/candidate section. Concretely:

Remove `import fetch_images as _fi` (line 19). KEEP `import build_csv` (now used by `export_rows`). Update the module docstring to drop "fetched image candidates", "the chosen image", and "(via fetch_images)"/Pillow.

Replace the schema + connect + candidate functions with:

```python
DAY_FACT_COLUMNS = ("kanji", "reading_ja", "reading_en", "season",
                    "subseason", "category", "gloss_en")
DAY_PROSE_COLUMNS = ("translation_en", "description_ja", "description_en")
_DAY_WRITABLE = set(DAY_FACT_COLUMNS) | set(DAY_PROSE_COLUMNS)

# Bumped when the on-disk schema changes; connect() migrates older DBs forward.
# v1: image pivot (ADR 0026) — dropped the candidates table + chosen_candidate_id.
_SCHEMA_VERSION = 1

_SCHEMA = """
CREATE TABLE IF NOT EXISTS days (
    date TEXT PRIMARY KEY,
    kanji TEXT NOT NULL DEFAULT '',
    reading_ja TEXT NOT NULL DEFAULT '',
    reading_en TEXT NOT NULL DEFAULT '',
    season TEXT NOT NULL DEFAULT '',
    subseason TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT '',
    gloss_en TEXT NOT NULL DEFAULT '',
    translation_en TEXT NOT NULL DEFAULT '',
    description_ja TEXT NOT NULL DEFAULT '',
    description_en TEXT NOT NULL DEFAULT '',
    approved INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT ''
);
"""


def _now():
    return dt.datetime.now().isoformat(timespec="seconds")


def _migrate(conn):
    """Forward-migrate an older on-disk schema, preserving every `days` row.
    Idempotent and guarded by PRAGMA user_version."""
    version = conn.execute("PRAGMA user_version").fetchone()[0]
    if version >= _SCHEMA_VERSION:
        return
    # v0 -> v1 (ADR 0026): drop the chosen_candidate_id column and candidates
    # table. Column drop first so the FK reference is gone before the table.
    cols = {r[1] for r in conn.execute("PRAGMA table_info(days)")}
    if "chosen_candidate_id" in cols:
        if sqlite3.sqlite_version_info >= (3, 35, 0):
            conn.execute("ALTER TABLE days DROP COLUMN chosen_candidate_id")
        else:
            _rebuild_days_dropping_chosen(conn)
    conn.execute("DROP TABLE IF EXISTS candidates")
    conn.execute(f"PRAGMA user_version = {_SCHEMA_VERSION}")
    conn.commit()


def _rebuild_days_dropping_chosen(conn):
    """Fallback for SQLite < 3.35 (no ALTER TABLE DROP COLUMN): rebuild `days`
    copying every retained column."""
    keep = ("date", *DAY_FACT_COLUMNS, *DAY_PROSE_COLUMNS,
            "approved", "created_at", "updated_at")
    collist = ", ".join(keep)
    conn.executescript(_SCHEMA.replace("days", "days_new"))
    conn.execute(f"INSERT INTO days_new ({collist}) SELECT {collist} FROM days")
    conn.execute("DROP TABLE days")
    conn.execute("ALTER TABLE days_new RENAME TO days")


def connect(path):
    # check_same_thread=False: the review webapp serves requests synchronously
    # (never concurrently) but serve_forever() runs on a thread distinct from the
    # one that called connect(); tests spin the server on a background thread. No
    # concurrent access occurs, so relaxing the same-thread guard is safe.
    conn = sqlite3.connect(str(path), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.executescript(_SCHEMA)
    conn.commit()
    _migrate(conn)
    return conn
```

Keep `seed_days`, `get_day`, `list_days`, `set_day_fields`, `set_approved` unchanged. DELETE `CANDIDATE_STORE_COLUMNS`, `add_candidate`, `get_candidates`, `clear_candidates`, `set_chosen`, and `_contract_row`. Replace `export_rows` + `pending_dates` with:

```python
# The fields the contract/validator require non-empty for a shippable row
# (mirrors scripts/content/validator.py — a day that passes here passes assemble).
_REQUIRED_FOR_EXPORT = ("kanji", "reading_ja", "reading_en", "translation_en",
                        "description_ja", "description_en")


def _is_complete(day):
    return all((day.get(c) or "").strip() for c in _REQUIRED_FOR_EXPORT)


def export_rows(conn, date_from=None, date_to=None):
    """Approved, prose-complete days as 7-column contract rows (keyed exactly by
    build_csv.CONTRACT_COLUMNS). Images are no longer part of the gate (ADR 0026)."""
    out = []
    for day in list_days(conn, date_from, date_to, status="approved"):
        if not _is_complete(day):
            continue
        out.append({c: day[c] for c in build_csv.CONTRACT_COLUMNS})
    return out


def pending_dates(conn, date_from=None, date_to=None):
    exportable = {r["date"] for r in export_rows(conn, date_from, date_to)}
    return [d["date"] for d in list_days(conn, date_from, date_to)
            if d["date"] not in exportable]
```

- [ ] **Step 4: Run tests to verify pass**

Run: `python3 scripts/content/fill/test_store.py`
Expected: PASS (all remaining seed/field/list tests plus the two new migration/export tests). No `candidates`/`fetch_images` references remain.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/store.py scripts/content/fill/test_store.py
git commit -m "feat(fill): text-only store schema + review.db migration + prose-gated export"
```

---

### Task 3: `webapp.py` → text-only review API

Remove the candidate route, the image fields in the summary/get, and `chosen_candidate_id` from PATCH.

**Files:**
- Modify: `scripts/content/fill/webapp.py`
- Test: `scripts/content/fill/test_webapp.py`

**Interfaces:**
- Consumes: text-only `store` (Task 2).
- Produces: `day_summary(day)` (no `candidate_count` param); `handle_list_days`/`handle_get_day` without candidates; `handle_patch_day` whitelist = `_PROSE_FIELDS ∪ {approved}`; no `/candidates/*.jpg` route; `make_server(conn, web_dir, host, port)` (drop `images_dir`).

- [ ] **Step 1: Update the tests first (RED)**

In `scripts/content/fill/test_webapp.py`: DELETE `test_get_day_includes_candidates`; in `test_day_summary_flags` drop the `has_image`/`candidate_count` assertions (keep `has_prose`/`approved`); in `test_patch_day_bad_candidate_does_not_persist_prose` — the "bad candidate" path no longer exists, so replace it with a test that an unknown field is rejected and nothing persists:

```python
def test_patch_day_rejects_unknown_field_and_persists_nothing():
    conn = store.connect(":memory:")
    store.seed_days(conn, [{"date": "2026-07-07", "kanji": "七夕"}])
    try:
        webapp.handle_patch_day(conn, "2026-07-07",
                                {"description_ja": "和文", "bogus": 1})
        assert False, "expected ValueError"
    except ValueError:
        pass
    assert store.get_day(conn, "2026-07-07")["description_ja"] == ""  # nothing written
```

Keep `test_patch_day_edits_prose_and_approves`, `test_patch_day_rejects_bad_input`, `test_make_server_serves_api_over_http` (drop any candidate assertions inside them).

- [ ] **Step 2: Run to verify it fails**

Run: `python3 scripts/content/fill/test_webapp.py`
Expected: FAIL (references to removed behavior / new test not yet satisfied).

- [ ] **Step 3: Edit `webapp.py`**

- Update the module docstring: "edit readings/prose, approve the day" (drop "pick the image").
- `day_summary`: drop the `candidate_count` parameter and the `has_image` key:

```python
def day_summary(day):
    return {
        "date": day["date"], "kanji": day["kanji"], "approved": day["approved"],
        "reading_ja": day["reading_ja"], "season": day["season"],
        "subseason": day["subseason"],
        "has_prose": bool(day["translation_en"] and day["description_ja"]
                          and day["description_en"]),
    }
```

- `handle_list_days`: drop the candidate count:

```python
def handle_list_days(conn, date_from=None, date_to=None, status=None):
    return [day_summary(day) for day in store.list_days(conn, date_from, date_to, status)]
```

- `handle_get_day`: drop `day["candidates"] = ...` (return the plain day).
- `handle_patch_day`: whitelist `known = set(_PROSE_FIELDS) | {"approved"}`; remove the `if "chosen_candidate_id" in body: store.set_chosen(...)` block. Prose write + approved write remain (prose first is fine; neither raises since the whitelist is pre-checked).
- `make_server`: drop the `images_dir` parameter and the entire `if parts[:1] == ["candidates"] ...` route block in `do_GET`.

- [ ] **Step 4: Run tests to verify pass**

Run: `python3 scripts/content/fill/test_webapp.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/webapp.py scripts/content/fill/test_webapp.py
git commit -m "feat(fill): text-only review API (drop candidate route + chosen field)"
```

---

### Task 4: `fill.py` → prose-only generate + fixed compile

Generate prose only, compile to the 7-column contract without `--image-base-url`, relocate `load_dotenv` (it lived in the deleted `fetch_images`), and drop all image imports/args.

**Files:**
- Modify: `scripts/content/fill/fill.py`
- Test: `scripts/content/fill/test_fill.py`

**Interfaces:**
- Consumes: text-only `store` (Task 2), `build_csv.CONTRACT_COLUMNS` (Task 1).
- Produces: `fill.load_dotenv(path=ENV_FILE)`; `write_contract_csv(rows, out_csv)` (no `out_images`); prose-only `cmd_generate`; `cmd_compile` with no image flag. REMOVED: `generate_images`.

- [ ] **Step 1: Update tests first (RED)**

In `scripts/content/fill/test_fill.py`: DELETE `test_generate_images_stores_candidates_and_clears_first` and `test_compile_writes_contract_csv_and_copies_image`. Add a text-only compile test:

```python
def test_compile_exports_approved_complete_days_to_7col_csv(tmp_path):
    db = tmp_path / "r.db"
    conn = store.connect(db)
    store.seed_days(conn, [{"date": "2026-05-05", "kanji": "菖蒲",
                            "reading_ja": "しょうぶ", "reading_en": "shoubu"}])
    store.set_day_fields(conn, "2026-05-05", translation_en="iris",
                         description_ja="和文", description_en="English")
    store.set_approved(conn, "2026-05-05", True)
    out_csv = tmp_path / "kigo.csv"
    rows = store.export_rows(conn)
    n = fill.write_contract_csv(rows, out_csv)
    assert n == 1
    import csv as _csv
    got = list(_csv.DictReader(out_csv.open(encoding="utf-8")))
    assert list(got[0].keys()) == list(build_csv.CONTRACT_COLUMNS)
    assert got[0]["kanji"] == "菖蒲" and "image_id" not in got[0]
```

Keep `test_spine_seeds_365_days`, `test_spine_respects_approve_freeze`, and the three `test_generate_descriptions_*` tests. Ensure `import build_csv` is present.

- [ ] **Step 2: Run to verify it fails**

Run: `python3 scripts/content/fill/test_fill.py`
Expected: FAIL (e.g. `write_contract_csv` still requires `out_images`, or import errors).

- [ ] **Step 3: Edit `fill.py`**

Update the module docstring (generate = "author prose for a date range"; drop image/Pillow references). Then:

- **Imports:** remove `import fetch_images`, `import shutil`. Keep `import csv`, `import build_csv`, `import subprocess`, `import os`, `import functools`. Add the env-file constant and relocated helper near the top (after `DEFAULT_MANIFEST`):

```python
ENV_FILE = HERE / ".env"


def load_dotenv(path=ENV_FILE):
    """Populate os.environ from a simple KEY=VALUE .env file (does not override
    values already set in the real environment). Relocated from the removed
    fetch_images module (ADR 0026)."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())
```

- **DELETE `generate_images`** entirely.
- **`cmd_generate`:** call `load_dotenv()` (local now), keep the prose block, and DELETE the whole `if not args.no_images:` block. Since prose is the only phase, drop the `if not args.no_descriptions:` guard (always generate prose):

```python
def cmd_generate(args):
    # Load the gitignored .env so ANTHROPIC_API_KEY can live there; setdefault
    # means a real exported env var still wins over the file.
    load_dotenv()
    conn = store.connect(args.db)
    days = _select_days(conn, args.date_from, args.date_to, args.force)
    if not days:
        print("no days to generate in range (all approved? run with --force)",
              file=sys.stderr)
        return 1
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("error: set ANTHROPIC_API_KEY (in .env or the environment)", file=sys.stderr)
        return 2
    call_llm = functools.partial(describe_via_claude.call_claude, api_key=api_key,
                                 model=args.model, max_tokens=8000)
    written, errors = generate_descriptions(conn, days, call_llm)
    print(f"descriptions: wrote {written} day(s)")
    for e in errors:
        print("  " + e, file=sys.stderr)
    return 0
```

- **`write_contract_csv`:** drop the JPEG copy + `out_images`:

```python
def write_contract_csv(rows, out_csv):
    """Write the exact 7-column contract CSV (build_csv.CONTRACT_COLUMNS) from
    store.export_rows output. Returns row count."""
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=build_csv.CONTRACT_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    return len(rows)
```

- **`cmd_compile`:** drop `out_images` + `--image-base-url`; fix the "no rows" message:

```python
def cmd_compile(args):
    conn = store.connect(args.db)
    rows = store.export_rows(conn, args.date_from, args.date_to)
    if not rows:
        print("error: no approved, prose-complete days in range", file=sys.stderr)
        return 1
    n = write_contract_csv(rows, args.out_csv)
    print(f"wrote {n} approved row(s) to {args.out_csv}")
    pending = store.pending_dates(conn, args.date_from, args.date_to)
    if pending:
        print(f"  skipped {len(pending)} unapproved/incomplete day(s) in range", file=sys.stderr)
    assemble = REPO_ROOT / "scripts" / "content" / "assemble.py"
    cmd = [sys.executable, str(assemble), "--csv", str(args.out_csv),
           "--out", str(args.manifest_out)]
    return subprocess.run(cmd).returncode
```

- **`cmd_review`:** `make_server` no longer takes `images`; call `webapp.make_server(conn, HERE / "web", host=args.host, port=args.port)`.
- **Argparse:** from the `generate` parser remove `--no-descriptions`, `--no-images`, `--out-images`, `--primary`, `--fallback`, `--no-fallback`, `--no-japanese`, `--no-wikipedia`, `--candidates`, `--per-page`, `--min-width`, `--min-height`, `--sleep` (keep `--db`, `--from`, `--to`, `--force`, `--model`). From `compile` remove `--out-images` and `--image-base-url`. From `review` remove `--images`.

- [ ] **Step 4: Run tests to verify pass**

Run: `python3 scripts/content/fill/test_fill.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fill.py scripts/content/fill/test_fill.py
git commit -m "feat(fill): prose-only generate + 7-col compile; relocate load_dotenv"
```

---

### Task 5: `web/` SPA → text-only editor

Remove the candidate gallery, the "image chosen" dot, the chosen-radio wiring, and the image empty-state copy.

**Files:**
- Modify: `scripts/content/fill/web/app.js`
- Modify: `scripts/content/fill/web/index.html`
- Modify: `scripts/content/fill/web/style.css`

- [ ] **Step 1: Edit `app.js`**
- In `renderIndex`, remove the `has_image` dot line (`<span class="dot ${d.has_image ? "on" : ""}" title="image chosen"></span>`); keep the prose dot + approved check.
- In `renderEditor`, remove the `<h2 class="sec-title">image · …</h2>` heading and the `<div class="gallery">${renderCandidates(day)}</div>` line.
- DELETE the entire `renderCandidates` function.
- In `wireEditor`, remove the `for (const el of document.querySelectorAll('input[name="chosen"]')) …` block.
- In `saveEditor`, remove the `const chosen = …; if (chosen) body.chosen_candidate_id = …` lines (body now carries only the `[data-key]` fields + `approved`).

- [ ] **Step 2: Edit `index.html`**
- Change the empty-state hint (`index.html:54`) from "…correct inline, choose one image, then approve." to "Read the Japanese top-to-bottom, correct inline, then approve."

- [ ] **Step 3: Edit `style.css`**
- Remove the candidate/gallery rules (`.gallery`, `.gallery__empty`, `.cand`, `.cand__img`, `.cand__badge`, `.cand__ref`, `.cand__meta`, `.cand__src`, `.is-chosen`, `.is-ref`). Leave every other selector.

- [ ] **Step 4: Smoke-test the server end-to-end**

Run (uses the migrated real DB read-only via a temp copy):
```bash
cd /Users/aonsager/projects/kigo
python3 - <<'PY'
import sys, threading, urllib.request, json, tempfile, pathlib, time
sys.path.insert(0, "scripts/content/fill")
import store, webapp
conn = store.connect(":memory:")
store.seed_days(conn, [{"date":"2026-05-05","kanji":"菖蒲","reading_ja":"しょうぶ","reading_en":"shoubu"}])
srv = webapp.make_server(conn, "scripts/content/fill/web", host="127.0.0.1", port=8731)
threading.Thread(target=srv.serve_forever, daemon=True).start(); time.sleep(0.3)
days = json.load(urllib.request.urlopen("http://127.0.0.1:8731/api/days"))
assert "has_image" not in days[0], days[0]
day = json.load(urllib.request.urlopen("http://127.0.0.1:8731/api/days/2026-05-05"))
assert "candidates" not in day, day
html = urllib.request.urlopen("http://127.0.0.1:8731/").read().decode()
assert "choose one image" not in html
js = urllib.request.urlopen("http://127.0.0.1:8731/app.js").read().decode()
assert "renderCandidates" not in js and "chosen_candidate_id" not in js
# /candidates route is gone → 404
code = 0
try:
    urllib.request.urlopen("http://127.0.0.1:8731/candidates/x.jpg")
except urllib.error.HTTPError as e:
    code = e.code
assert code == 404, code
srv.shutdown()
print("WEB SMOKE OK")
PY
```
Expected: `WEB SMOKE OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/web/
git commit -m "feat(fill): text-only review editor (remove candidate gallery)"
```

---

### Task 6: Delete `fetch_images.py` and image artifacts

Nothing imports `fetch_images` anymore (Tasks 2 + 4 removed the last importers). Remove it, its test, and the download artifacts.

**Files:**
- Delete: `scripts/content/fill/fetch_images.py`, `scripts/content/fill/test_fetch_images.py`, `scripts/content/fill/downloads/` (dir), `scripts/content/fill/candidates.csv`

- [ ] **Step 1: Confirm no remaining importer/reference**

Run:
```bash
cd /Users/aonsager/projects/kigo
grep -rn "fetch_images" scripts/content/fill/ --include=*.py | grep -v "test_fetch_images.py:" || echo "NO fetch_images IMPORTERS"
```
Expected: `NO fetch_images IMPORTERS` (only its own file/test would match, which we delete). If any live `.py` still imports it, STOP — a prior task missed a reference.

- [ ] **Step 2: Delete**

```bash
git rm scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py scripts/content/fill/candidates.csv
git rm -r scripts/content/fill/downloads
```
(If `candidates.csv`/`downloads/` are untracked rather than tracked, use plain `rm`/`rm -r`; if absent, skip — report which.)

- [ ] **Step 3: Run the whole fill/ suite green**

Run:
```bash
cd /Users/aonsager/projects/kigo
for t in test_store test_fill test_webapp; do echo "== $t =="; python3 scripts/content/fill/$t.py || exit 1; done
```
Expected: all three suites pass. `test_fetch_images.py` is gone.

- [ ] **Step 4: End-to-end compile against a real approved day**

Prove the repaired contract boundary end-to-end (uses a throwaway DB so the real `review.db` and bundled manifest are untouched):
```bash
cd /Users/aonsager/projects/kigo
python3 - <<'PY'
import sys, tempfile, pathlib, subprocess
sys.path.insert(0, "scripts/content/fill")
import store, fill
d = pathlib.Path(tempfile.mkdtemp())
conn = store.connect(d/"r.db")
store.seed_days(conn, [{"date":"2026-05-05","kanji":"菖蒲","reading_ja":"しょうぶ","reading_en":"shoubu"}])
store.set_day_fields(conn, "2026-05-05", translation_en="iris", description_ja="和文", description_en="English")
store.set_approved(conn, "2026-05-05", True)
class A: pass
a=A(); a.db=d/"r.db"; a.date_from=None; a.date_to=None
a.out_csv=d/"kigo.csv"; a.manifest_out=d/"manifest.json"
rc = fill.cmd_compile(a)
print("compile rc:", rc)
assert rc == 0, rc
import json
m = json.load((d/"manifest.json").open())
assert "2026-05-05" in m["dailyMap"], list(m["dailyMap"])[:3]
assert "imageBaseURL" not in m
print("E2E COMPILE OK — manifest dailyMap has the approved day, no image fields")
PY
```
Expected: `compile rc: 0` then `E2E COMPILE OK …`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(fill): delete fetch_images + candidate artifacts (image sourcing retired)"
```

---

### Task 7: Docs — READMEs + decision record

**Files:**
- Modify: `scripts/content/fill/README.md`
- Modify: `content/README.md`
- Modify: `docs/adr/0026-uniform-per-sekki-bundled-backdrops.md` (append a note) — or create `docs/adr/0027-content-fill-descoped-to-text-only.md`

- [ ] **Step 1: Rewrite `scripts/content/fill/README.md`**

Remove the image stages (fetch/select), the "legal posture"/attribution sections, and all image flags. Document the text-only flow: `spine` (seed 365 day-facts) → `generate --from --to` (Claude prose only; needs `ANTHROPIC_API_KEY` in `.env` or env) → `review` (local web editor: edit readings/translation/descriptions, approve) → `compile` (export approved + prose-complete days to the **7-column** `content/kigo-2026.csv`, then `assemble.py` → manifest). Note the `review.db` v1 migration is automatic. State that image sourcing was retired by ADR 0026 and the manifest ships per-Sekki bundled backdrops instead.

- [ ] **Step 2: Update `content/README.md`**

Replace any "13-column" / "14-column contract" description and image-column references with the current **7-column** contract (`date, kanji, reading_ja, reading_en, translation_en, description_ja, description_en`). Remove image/attribution column docs.

- [ ] **Step 3: Record the decision**

Append a dated note to ADR 0026 (Consequences): "The `scripts/content/fill/` tool, previously flagged as an obsolete follow-up, has been descoped to a text-only editorial review tool (image sourcing removed, `review.db` migrated v0→v1, 7-column contract restored). See plan `2026-07-23-content-fill-text-only-editorial`." (If the project prefers a standalone ADR, create `0027-content-fill-descoped-to-text-only.md` in the current ADR header format instead, and cross-link 0026.)

- [ ] **Step 4: Commit**

```bash
git add scripts/content/fill/README.md content/README.md docs/adr/
git commit -m "docs(fill): document text-only editorial flow + 7-col contract (ADR 0026)"
```

---

## Self-Review

**Spec coverage:**
- Text-only four-verb shape → Tasks 1–4 (build_csv, store, webapp, fill). ✔
- `review.db` migration preserving every `days` row → Task 2 (`_migrate`, version-guarded, idempotent, tested against a hand-built v0 DB with data). ✔
- Prose-completeness ship gate (mirrors `validator.py`) → Task 2 (`_REQUIRED_FOR_EXPORT`, tested). ✔
- Contract repair (7-col, no `--image-base-url`, no 0-row skip) → Tasks 1, 4, and the Task 6 end-to-end compile. ✔
- Editorial review UI (no candidate gallery/route) → Tasks 3 + 5. ✔
- Deletions (`fetch_images`, candidates table/fns, image tests) → Tasks 2, 4, 6. ✔
- `load_dotenv` relocation (functional dependency that survives deleting `fetch_images`) → Task 4. ✔
- Docs + decision record → Task 7. ✔
- Out of scope respected: no change to `assemble.py`/`csv_parser.py`/`validator.py`, no app/manifest change, compile stays replace-not-merge. ✔

**Placeholder scan:** none — every step has concrete code or exact edit targets. ADR number choice (append to 0026 vs new 0027) is a stated either/or, not a gap.

**Type/interface consistency:** `build_csv.CONTRACT_COLUMNS` (Task 1) is consumed identically by `store.export_rows` (Task 2) and `fill.write_contract_csv` (Task 4). `store` loses `add_candidate`/`get_candidates`/`clear_candidates`/`set_chosen`/`_contract_row`; Task 3 (`handle_get_day`/`handle_list_days`) and Task 4 (`generate_images` deleted) no longer call them. `webapp.day_summary` loses its `candidate_count` param (Task 3) and `make_server` loses `images_dir` (Task 3), matched by `fill.cmd_review` (Task 4). `fill.load_dotenv` replaces the deleted `fetch_images.load_dotenv`, called in `cmd_generate` (Task 4). Ordering keeps each task's own test suite green and defers deleting `fetch_images.py` until after its last importer is gone (Task 6).
