# Content-fill Review Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-run CSV-chain content-fill workflow with a SQLite-backed review store, a four-subcommand CLI wrapper (`spine`/`generate`/`compile`/`review`), and a local web UI that is the single per-day review gate — while keeping `assemble.py` as the untouched final validation.

**Architecture:** A SQLite DB (`review.db`) becomes the editorial source of truth between the deterministic generators and the `assemble.py` gate. `spine` seeds day facts; `generate <range>` authors prose and fetches image candidates into the store for *unapproved* days only; a local `http.server`-based web UI edits fields, picks the image, and approves days; `compile [range]` exports approved days to the existing 14-column `content/kigo-2026.csv` contract and runs `assemble.py`. The proven stage scripts (`assign_dates.py`, `describe*.py`, `fetch_images.py`) stay the engine — their pure functions are imported; only `fetch_images.py` gets a small extract-a-function refactor.

**Tech Stack:** Python 3 stdlib (`sqlite3`, `http.server`, `urllib`, `csv`, `argparse`), Pillow (already the pipeline's only third-party dep, used only in image processing), vanilla JavaScript (no framework, no build step).

## Global Constraints

- **Stdlib only + Pillow.** No new third-party dependencies. The web UI is vanilla JS served by `http.server` — no Node toolchain, no framework, no build step.
- **Test convention (match the existing files).** Tests are plain module-level `def test_*()` functions with a `if __name__ == "__main__":` runner that calls each and prints `PASS <name>` / `ALL PASS`. **No pytest.** Run a suite with `python3 scripts/content/fill/<test_file>.py`. Copy the runner block verbatim from `scripts/content/fill/test_fetch_images.py:579-584`.
- **Contract is exact.** The final CSV columns must equal `build_csv.CONTRACT_COLUMNS` in this exact order: `date, kanji, reading_ja, reading_en, translation_en, description_ja, description_en, image_id, attribution_title_ja, attribution_title_en, attribution_credit_ja, attribution_credit_en, attribution_license_ja, attribution_license_en`.
- **`assemble.py` is untouched** and remains the end-to-end gate: `python3 scripts/content/assemble.py --csv content/kigo-2026.csv --out Resources/manifest.json`.
- **`image_id` = `kigo-MM-DD`** (via `fetch_images.image_id_for(date)`).
- **The DB is working state, gitignored** (`scripts/content/fill/review.db*`); `content/kigo-2026.csv` stays the committed, diffable, shipped artifact.
- **The one reconciliation rule — "approved freezes":** a day with `approved=1` is never mutated by `spine`/`generate` (only `--force` overrides); unapproved days are drafts, fully regenerated.
- **All content loads through `ContentSource`** (project convention) — this pipeline only produces the CSV/manifest the existing loader already consumes; do not add new runtime load paths.

## File Structure

**Create:**
- `scripts/content/fill/store.py` — SQLite schema + all data accessors (connect, seed, day/candidate CRUD, chosen validation, contract export). One responsibility: persistence.
- `scripts/content/fill/fill.py` — the CLI entrypoint with four subcommands (`spine`, `generate`, `compile`, `review`). Orchestration only; imports store + stage functions.
- `scripts/content/fill/webapp.py` — pure request handlers over the store (`handle_list_days`, `handle_get_day`, `handle_patch_day`, `day_summary`) plus the thin `http.server` adapter. Split from `fill.py` so the routing logic is unit-testable without a socket.
- `scripts/content/fill/web/index.html`, `web/app.js`, `web/style.css` — the vanilla-JS SPA.
- `scripts/content/fill/test_store.py`, `test_fill.py`, `test_webapp.py` — one test file per new module.
- `docs/adr/0025-sqlite-editorial-review-store.md` — records the store decision.

**Modify:**
- `scripts/content/fill/fetch_images.py` — extract `fetch_candidates_for_row(...)` from `cmd_fetch`'s per-row loop (dependency-injectable download + wiki lookup) so both `cmd_fetch` and `generate` reuse it. `test_fetch_images.py` gains a test for it.
- `scripts/content/fill/README.md` — document the wrapper + web UI as the new front door.

---

### Task 1: SQLite store — schema + day accessors

**Files:**
- Create: `scripts/content/fill/store.py`
- Test: `scripts/content/fill/test_store.py`

**Interfaces:**
- Consumes: nothing (foundation).
- Produces:
  - `DAY_FACT_COLUMNS = ("kanji","reading_ja","reading_en","season","subseason","category","gloss_en")`
  - `DAY_PROSE_COLUMNS = ("translation_en","description_ja","description_en")`
  - `connect(path) -> sqlite3.Connection` (creates schema, sets `foreign_keys=ON`, `journal_mode=WAL`; `row_factory = sqlite3.Row`)
  - `seed_days(conn, rows, force=False) -> (seeded:int, skipped:int)` — `rows` are dicts keyed by `date` + `DAY_FACT_COLUMNS`; upserts fact columns only; skips a day that already exists with `approved=1` unless `force`.
  - `get_day(conn, date) -> dict | None`
  - `list_days(conn, date_from=None, date_to=None, status=None) -> list[dict]` — `status` in `{None,"approved","unapproved"}`, ordered by date.
  - `set_day_fields(conn, date, **fields) -> None` — whitelists `DAY_FACT_COLUMNS + DAY_PROSE_COLUMNS`; bumps `updated_at`.
  - `set_approved(conn, date, approved) -> None`

- [ ] **Step 1: Write the failing test**

Create `scripts/content/fill/test_store.py`:

```python
"""Offline checks for the SQLite editorial review store
(scripts/content/fill/store.py). No network, no simulator. Matches the plain
test_* + __main__ runner convention of test_fetch_images.py.

Run directly:
    python3 scripts/content/fill/test_store.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store  # noqa: E402


def _mem():
    return store.connect(":memory:")


def _fact_row(date="2026-03-25", kanji="桜"):
    return {"date": date, "kanji": kanji, "reading_ja": "さくら",
            "reading_en": "sakura", "season": "spring", "subseason": "mid spring",
            "category": "plant", "gloss_en": "cherry blossom"}


def test_seed_inserts_facts():
    conn = _mem()
    seeded, skipped = store.seed_days(conn, [_fact_row()])
    assert (seeded, skipped) == (1, 0)
    day = store.get_day(conn, "2026-03-25")
    assert day["kanji"] == "桜" and day["gloss_en"] == "cherry blossom"
    assert day["approved"] == 0 and day["chosen_candidate_id"] is None


def test_seed_upserts_facts_on_unapproved():
    conn = _mem()
    store.seed_days(conn, [_fact_row(kanji="桜")])
    seeded, skipped = store.seed_days(conn, [_fact_row(kanji="山桜")])
    assert (seeded, skipped) == (1, 0)
    assert store.get_day(conn, "2026-03-25")["kanji"] == "山桜"


def test_seed_skips_approved_unless_force():
    conn = _mem()
    store.seed_days(conn, [_fact_row(kanji="桜")])
    store.set_approved(conn, "2026-03-25", True)
    seeded, skipped = store.seed_days(conn, [_fact_row(kanji="山桜")])
    assert (seeded, skipped) == (0, 1)
    assert store.get_day(conn, "2026-03-25")["kanji"] == "桜"  # frozen
    seeded, skipped = store.seed_days(conn, [_fact_row(kanji="山桜")], force=True)
    assert (seeded, skipped) == (1, 0)
    assert store.get_day(conn, "2026-03-25")["kanji"] == "山桜"


def test_set_day_fields_updates_prose_only_whitelist():
    conn = _mem()
    store.seed_days(conn, [_fact_row()])
    store.set_day_fields(conn, "2026-03-25", description_ja="説明", description_en="desc",
                         translation_en="cherry-blossom viewing")
    day = store.get_day(conn, "2026-03-25")
    assert day["description_ja"] == "説明" and day["translation_en"] == "cherry-blossom viewing"
    try:
        store.set_day_fields(conn, "2026-03-25", approved=1)
    except ValueError:
        pass
    else:
        raise AssertionError("set_day_fields must reject non-whitelisted columns")


def test_list_days_filters_by_range_and_status():
    conn = _mem()
    store.seed_days(conn, [_fact_row("2026-01-01"), _fact_row("2026-03-25"),
                           _fact_row("2026-12-31")])
    store.set_approved(conn, "2026-03-25", True)
    in_range = store.list_days(conn, "2026-02-01", "2026-06-30")
    assert [d["date"] for d in in_range] == ["2026-03-25"]
    approved = store.list_days(conn, status="approved")
    assert [d["date"] for d in approved] == ["2026-03-25"]
    unapproved = store.list_days(conn, status="unapproved")
    assert [d["date"] for d in unapproved] == ["2026-01-01", "2026-12-31"]


if __name__ == "__main__":
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print("ALL PASS")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_store.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'store'` (or `AttributeError` once the file is stubbed).

- [ ] **Step 3: Write minimal implementation**

Create `scripts/content/fill/store.py`:

```python
#!/usr/bin/env python3
"""store.py — the SQLite editorial review store for the kigo-2026 fill workflow.

The editorial source of truth that sits between the deterministic generators
(spine facts, LLM prose, fetched image candidates) and the assemble.py gate.
Separates regenerable/derived data from durable human decisions (edits, the
chosen image, approval). One reconciliation rule — "approved freezes": an
approved day is never mutated by spine/generate; unapproved days are drafts.

Stdlib only. See docs/adr/0025-sqlite-editorial-review-store.md.
"""
import datetime as dt
import sqlite3

DAY_FACT_COLUMNS = ("kanji", "reading_ja", "reading_en", "season",
                    "subseason", "category", "gloss_en")
DAY_PROSE_COLUMNS = ("translation_en", "description_ja", "description_en")
_DAY_WRITABLE = set(DAY_FACT_COLUMNS) | set(DAY_PROSE_COLUMNS)

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
    chosen_candidate_id INTEGER REFERENCES candidates(id) ON DELETE SET NULL,
    approved INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS candidates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL REFERENCES days(date) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT '',
    search_term TEXT NOT NULL DEFAULT '',
    search_lang TEXT NOT NULL DEFAULT '',
    photographer TEXT NOT NULL DEFAULT '',
    license_ja TEXT NOT NULL DEFAULT '',
    license_en TEXT NOT NULL DEFAULT '',
    title_ja TEXT NOT NULL DEFAULT '',
    title_en TEXT NOT NULL DEFAULT '',
    source_url TEXT NOT NULL DEFAULT '',
    src_w INTEGER NOT NULL DEFAULT 0,
    src_h INTEGER NOT NULL DEFAULT 0,
    out_file TEXT NOT NULL DEFAULT '',
    usable TEXT NOT NULL DEFAULT 'yes',
    note TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_candidates_date ON candidates(date);
"""


def _now():
    return dt.datetime.now().isoformat(timespec="seconds")


def connect(path):
    conn = sqlite3.connect(str(path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.executescript(_SCHEMA)
    conn.commit()
    return conn


def seed_days(conn, rows, force=False):
    seeded = skipped = 0
    for row in rows:
        date = row["date"]
        existing = conn.execute("SELECT approved FROM days WHERE date = ?", (date,)).fetchone()
        if existing and existing["approved"] and not force:
            skipped += 1
            continue
        cols = list(DAY_FACT_COLUMNS)
        vals = [row.get(c, "") for c in cols]
        if existing:
            assignments = ", ".join(f"{c} = ?" for c in cols)
            conn.execute(f"UPDATE days SET {assignments}, updated_at = ? WHERE date = ?",
                         (*vals, _now(), date))
        else:
            placeholders = ", ".join(["?"] * (len(cols) + 3))
            conn.execute(
                f"INSERT INTO days (date, {', '.join(cols)}, created_at, updated_at) "
                f"VALUES ({placeholders})",
                (date, *vals, _now(), _now()))
        seeded += 1
    conn.commit()
    return seeded, skipped


def get_day(conn, date):
    row = conn.execute("SELECT * FROM days WHERE date = ?", (date,)).fetchone()
    return dict(row) if row else None


def list_days(conn, date_from=None, date_to=None, status=None):
    clauses, params = [], []
    if date_from:
        clauses.append("date >= ?"); params.append(date_from)
    if date_to:
        clauses.append("date <= ?"); params.append(date_to)
    if status == "approved":
        clauses.append("approved = 1")
    elif status == "unapproved":
        clauses.append("approved = 0")
    where = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    rows = conn.execute(f"SELECT * FROM days{where} ORDER BY date", params).fetchall()
    return [dict(r) for r in rows]


def set_day_fields(conn, date, **fields):
    bad = set(fields) - _DAY_WRITABLE
    if bad:
        raise ValueError(f"non-writable day columns: {sorted(bad)}")
    if not fields:
        return
    assignments = ", ".join(f"{c} = ?" for c in fields)
    conn.execute(f"UPDATE days SET {assignments}, updated_at = ? WHERE date = ?",
                 (*fields.values(), _now(), date))
    conn.commit()


def set_approved(conn, date, approved):
    conn.execute("UPDATE days SET approved = ?, updated_at = ? WHERE date = ?",
                 (1 if approved else 0, _now(), date))
    conn.commit()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_store.py`
Expected: `PASS test_...` for all five, then `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/store.py scripts/content/fill/test_store.py
git commit -m "feat(fill): SQLite review store — schema + day accessors"
```

---

### Task 2: store — candidate accessors + chosen validation

**Files:**
- Modify: `scripts/content/fill/store.py`
- Test: `scripts/content/fill/test_store.py`

**Interfaces:**
- Consumes: Task 1 store schema.
- Produces:
  - `CANDIDATE_STORE_COLUMNS = ("provider","search_term","search_lang","photographer","license_ja","license_en","title_ja","title_en","source_url","src_w","src_h","out_file","usable","note")`
  - `add_candidate(conn, date, cand) -> int` — inserts one candidate (reads only `CANDIDATE_STORE_COLUMNS` keys from `cand`, ignoring extras like the `candidate`/`chosen`/`image_id` keys `fetch_images.candidate_row` also emits); returns its new id.
  - `get_candidates(conn, date) -> list[dict]` (each includes `id`)
  - `clear_candidates(conn, date) -> None` — deletes all candidates for the date and nulls `chosen_candidate_id`.
  - `set_chosen(conn, date, candidate_id) -> None` — raises `ValueError` if the candidate does not belong to `date` or is reference-only (`usable == "no"`).

- [ ] **Step 1: Write the failing test**

Append to `scripts/content/fill/test_store.py` (before the `__main__` runner):

```python
def _cand(out_file="kigo-03-25__c1.jpg", usable="yes", provider="pexels"):
    return {"provider": provider, "search_term": "桜", "search_lang": "ja-JP",
            "photographer": "Ansel", "license_ja": "Pexels ライセンス",
            "license_en": "Pexels License", "title_ja": "桜", "title_en": "cherry blossom",
            "source_url": "https://ex/1", "src_w": 1000, "src_h": 1500,
            "out_file": out_file, "usable": usable, "note": "",
            # extras that candidate_row also emits and add_candidate must ignore:
            "candidate": 1, "chosen": "", "image_id": "kigo-03-25"}


def test_add_and_get_candidates():
    conn = _mem()
    store.seed_days(conn, [_fact_row()])
    cid = store.add_candidate(conn, "2026-03-25", _cand())
    assert isinstance(cid, int)
    cands = store.get_candidates(conn, "2026-03-25")
    assert len(cands) == 1 and cands[0]["id"] == cid
    assert cands[0]["photographer"] == "Ansel" and cands[0]["src_w"] == 1000


def test_set_chosen_validates_ownership_and_usable():
    conn = _mem()
    store.seed_days(conn, [_fact_row(), _fact_row("2026-04-01")])
    good = store.add_candidate(conn, "2026-03-25", _cand())
    ref_only = store.add_candidate(conn, "2026-03-25", _cand(out_file="c2.jpg", usable="no"))
    other = store.add_candidate(conn, "2026-04-01", _cand(out_file="c3.jpg"))
    store.set_chosen(conn, "2026-03-25", good)
    assert store.get_day(conn, "2026-03-25")["chosen_candidate_id"] == good
    for bad in (ref_only, other, 9999):
        try:
            store.set_chosen(conn, "2026-03-25", bad)
        except ValueError:
            continue
        raise AssertionError(f"set_chosen should reject candidate {bad}")


def test_clear_candidates_resets_chosen():
    conn = _mem()
    store.seed_days(conn, [_fact_row()])
    cid = store.add_candidate(conn, "2026-03-25", _cand())
    store.set_chosen(conn, "2026-03-25", cid)
    store.clear_candidates(conn, "2026-03-25")
    assert store.get_candidates(conn, "2026-03-25") == []
    assert store.get_day(conn, "2026-03-25")["chosen_candidate_id"] is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_store.py`
Expected: FAIL — `AttributeError: module 'store' has no attribute 'add_candidate'`.

- [ ] **Step 3: Write minimal implementation**

Append to `scripts/content/fill/store.py`:

```python
CANDIDATE_STORE_COLUMNS = ("provider", "search_term", "search_lang", "photographer",
                           "license_ja", "license_en", "title_ja", "title_en",
                           "source_url", "src_w", "src_h", "out_file", "usable", "note")


def add_candidate(conn, date, cand):
    cols = list(CANDIDATE_STORE_COLUMNS)
    vals = [cand.get(c, "") for c in cols]
    placeholders = ", ".join(["?"] * (len(cols) + 1))
    cur = conn.execute(
        f"INSERT INTO candidates (date, {', '.join(cols)}) VALUES ({placeholders})",
        (date, *vals))
    conn.commit()
    return cur.lastrowid


def get_candidates(conn, date):
    rows = conn.execute("SELECT * FROM candidates WHERE date = ? ORDER BY id",
                        (date,)).fetchall()
    return [dict(r) for r in rows]


def clear_candidates(conn, date):
    conn.execute("UPDATE days SET chosen_candidate_id = NULL, updated_at = ? WHERE date = ?",
                 (_now(), date))
    conn.execute("DELETE FROM candidates WHERE date = ?", (date,))
    conn.commit()


def set_chosen(conn, date, candidate_id):
    row = conn.execute("SELECT date, usable FROM candidates WHERE id = ?",
                       (candidate_id,)).fetchone()
    if row is None or row["date"] != date:
        raise ValueError(f"candidate {candidate_id} does not belong to {date}")
    if (row["usable"] or "").strip().lower() == "no":
        raise ValueError(f"candidate {candidate_id} is reference-only, not shippable")
    conn.execute("UPDATE days SET chosen_candidate_id = ?, updated_at = ? WHERE date = ?",
                 (candidate_id, _now(), date))
    conn.commit()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_store.py`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/store.py scripts/content/fill/test_store.py
git commit -m "feat(fill): store candidate accessors + chosen validation"
```

---

### Task 3: store — contract export of approved days

**Files:**
- Modify: `scripts/content/fill/store.py`
- Test: `scripts/content/fill/test_store.py`

**Interfaces:**
- Consumes: Task 1–2 store; `fetch_images.image_id_for`, `fetch_images.image_row_from_candidate`, `build_csv.CONTRACT_COLUMNS`.
- Produces:
  - `export_rows(conn, date_from=None, date_to=None) -> list[dict]` — one dict per **approved** day in range that has a `chosen_candidate_id`. Each dict has all 14 `CONTRACT_COLUMNS` keys plus a private `"_out_file"` (the chosen candidate's local JPEG filename, for the compile copy step). Skips approved-but-unchosen and unapproved days silently (compile reports them).
  - `pending_dates(conn, date_from=None, date_to=None) -> list[str]` — dates in range that are NOT exportable (unapproved, or approved without a chosen candidate); for compile's stderr report.

- [ ] **Step 1: Write the failing test**

Append to `scripts/content/fill/test_store.py`:

```python
def test_export_rows_only_approved_with_chosen():
    conn = _mem()
    store.seed_days(conn, [_fact_row("2026-03-25"), _fact_row("2026-04-01"),
                           _fact_row("2026-05-01")])
    # 03-25: fully ready + approved
    store.set_day_fields(conn, "2026-03-25", translation_en="cherry-blossom viewing",
                         description_ja="説明", description_en="desc")
    cid = store.add_candidate(conn, "2026-03-25", _cand())
    store.set_chosen(conn, "2026-03-25", cid)
    store.set_approved(conn, "2026-03-25", True)
    # 04-01: approved but no chosen image
    store.set_approved(conn, "2026-04-01", True)
    # 05-01: has everything but not approved
    c2 = store.add_candidate(conn, "2026-05-01", _cand(out_file="kigo-05-01__c1.jpg"))
    store.set_chosen(conn, "2026-05-01", c2)

    rows = store.export_rows(conn)
    assert [r["date"] for r in rows] == ["2026-03-25"]
    r = rows[0]
    import build_csv
    assert set(build_csv.CONTRACT_COLUMNS).issubset(r.keys())
    assert r["image_id"] == "kigo-03-25"
    assert r["translation_en"] == "cherry-blossom viewing"
    assert r["attribution_title_ja"] == "桜"
    assert r["attribution_credit_en"] == "Photo: Ansel / Pexels"
    assert r["attribution_license_en"] == "Pexels License"
    assert r["_out_file"] == "kigo-03-25__c1.jpg"
    assert set(store.pending_dates(conn)) == {"2026-04-01", "2026-05-01"}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_store.py`
Expected: FAIL — `AttributeError: module 'store' has no attribute 'export_rows'`.

- [ ] **Step 3: Write minimal implementation**

Append to `scripts/content/fill/store.py` (add the imports at the top of the file with the others):

```python
# add near the top of store.py, after `import sqlite3`:
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_csv  # noqa: E402  (CONTRACT_COLUMNS)
import fetch_images as _fi  # noqa: E402  (image_id_for, image_row_from_candidate)
```

```python
def _contract_row(day, cand):
    image_id = _fi.image_id_for(day["date"])
    cand_row = {"date": day["date"], "image_id": image_id,
                "title_ja": cand["title_ja"], "title_en": cand["title_en"],
                "photographer": cand["photographer"], "provider": cand["provider"],
                "license_ja": cand["license_ja"], "license_en": cand["license_en"]}
    attribution = _fi.image_row_from_candidate(cand_row)  # 8 IMAGE_COLUMNS fields
    row = {
        "date": day["date"], "kanji": day["kanji"],
        "reading_ja": day["reading_ja"], "reading_en": day["reading_en"],
        "translation_en": day["translation_en"],
        "description_ja": day["description_ja"], "description_en": day["description_en"],
        "image_id": image_id,
        "attribution_title_ja": attribution["attribution_title_ja"],
        "attribution_title_en": attribution["attribution_title_en"],
        "attribution_credit_ja": attribution["attribution_credit_ja"],
        "attribution_credit_en": attribution["attribution_credit_en"],
        "attribution_license_ja": attribution["attribution_license_ja"],
        "attribution_license_en": attribution["attribution_license_en"],
    }
    row["_out_file"] = cand["out_file"]
    return row


def export_rows(conn, date_from=None, date_to=None):
    out = []
    for day in list_days(conn, date_from, date_to, status="approved"):
        cid = day["chosen_candidate_id"]
        if cid is None:
            continue
        cand = conn.execute("SELECT * FROM candidates WHERE id = ?", (cid,)).fetchone()
        if cand is None:
            continue
        out.append(_contract_row(day, dict(cand)))
    return out


def pending_dates(conn, date_from=None, date_to=None):
    exportable = {r["date"] for r in export_rows(conn, date_from, date_to)}
    return [d["date"] for d in list_days(conn, date_from, date_to)
            if d["date"] not in exportable]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_store.py`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/store.py scripts/content/fill/test_store.py
git commit -m "feat(fill): store contract export of approved days"
```

---

### Task 4: Refactor fetch_images — extract `fetch_candidates_for_row`

**Files:**
- Modify: `scripts/content/fill/fetch_images.py:677-750` (the `cmd_fetch` per-row loop)
- Test: `scripts/content/fill/test_fetch_images.py`

**Interfaces:**
- Consumes: existing `build_ladder`, `collect_candidates`, `process_image`, `save_jpeg`, `candidate_row`, `_download_image`, `_wikipedia_lookup`.
- Produces:
  - `fetch_candidates_for_row(row, search_fns, out_images, *, aspect=(9.0, 19.5), max_edge=2340, jpeg_quality=82, min_width=800, min_height=1200, candidates=3, primary="pexels", fallback="pixabay", use_japanese=True, include_wikipedia=True, download=_download_image, wiki_lookup=_wikipedia_lookup) -> tuple[list[dict], list[str]]` — returns `(candidate_row dicts, error strings)` for one spine row, saving each processed JPEG to `out_images`. `download`/`wiki_lookup` are injectable so callers can test offline.
- `cmd_fetch` is refactored to call this per row (behavior unchanged).

- [ ] **Step 1: Write the failing test**

Append to `scripts/content/fill/test_fetch_images.py` (before the `__main__` runner):

```python
def test_fetch_candidates_for_row_uses_injected_search_and_download():
    import tempfile
    row = {"date": "2026-03-25", "kanji": "桜",
           "gloss_en": "cherry blossom", "reading_en": "sakura"}

    def fake_search(term, lang):
        return [{"photo_id": f"{term}-{lang}", "photographer": "Ansel",
                 "download_url": f"http://x/{term}", "source_url": "http://s",
                 "width": 1000, "height": 1500}]

    search_fns = {"pexels": fake_search, "pixabay": fake_search}
    made = fi.Image.new("RGB", (1000, 1500), (120, 120, 120))

    with tempfile.TemporaryDirectory() as tmp:
        rows, errors = fi.fetch_candidates_for_row(
            row, search_fns, Path(tmp), candidates=2, include_wikipedia=False,
            download=lambda url: made)
        assert errors == []
        assert len(rows) == 2
        assert rows[0]["provider"] == "pexels" and rows[0]["date"] == "2026-03-25"
        assert rows[0]["image_id"] == "kigo-03-25"
        for i, r in enumerate(rows, start=1):
            assert (Path(tmp) / f"kigo-03-25__c{i}.jpg").exists()
            assert r["out_file"] == f"kigo-03-25__c{i}.jpg"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: FAIL — `AttributeError: module 'fetch_images' has no attribute 'fetch_candidates_for_row'`.

- [ ] **Step 3: Write minimal implementation**

In `scripts/content/fill/fetch_images.py`, add this function directly above `cmd_fetch` (around line 677):

```python
def fetch_candidates_for_row(row, search_fns, out_images, *, aspect=(9.0, 19.5),
                             max_edge=2340, jpeg_quality=82, min_width=800,
                             min_height=1200, candidates=3, primary="pexels",
                             fallback="pixabay", use_japanese=True,
                             include_wikipedia=True, download=_download_image,
                             wiki_lookup=_wikipedia_lookup):
    """Acquire + process candidate images for one spine row. Returns
    (candidate_row dicts, error strings). Injecting `download`/`wiki_lookup`
    lets callers run offline; production wires the real network functions."""
    aspect_w, aspect_h = aspect
    errors = []
    ladder = build_ladder(row, primary=primary, fallback=fallback,
                          use_japanese=use_japanese)
    cands = collect_candidates(ladder, search_fns, min_width, min_height, candidates)
    row_out = []
    for i, cand in enumerate(cands, start=1):
        img = process_image(download(cand["download_url"]), aspect_w, aspect_h, max_edge)
        fname = f"{image_id_for(row['date'])}__c{i}.jpg"
        save_jpeg(img, out_images / fname, jpeg_quality)
        row_out.append(candidate_row(row, cand, i, fname, img.width, img.height))
    if include_wikipedia:
        try:
            wiki = wiki_lookup(row["kanji"], row.get("gloss_en") or row["reading_en"],
                               min_width, min_height)
            if wiki:
                idx = len(row_out) + 1
                img = process_image(download(wiki["download_url"]), aspect_w, aspect_h, max_edge)
                fname = f"{image_id_for(row['date'])}__c{idx}.jpg"
                save_jpeg(img, out_images / fname, jpeg_quality)
                row_out.append(candidate_row(row, wiki, idx, fname, img.width, img.height))
        except Exception as e:  # a bonus wiki candidate must not drop the stock ones
            errors.append(f"wikipedia: {e!r}")
    return row_out, errors
```

Then replace the body of the `for row in rows:` loop in `cmd_fetch` (lines ~699-737) with a call to it, preserving the existing stderr reporting:

```python
    out_rows, missing, errors = [], [], []
    for row in rows:
        try:
            row_out, row_errors = fetch_candidates_for_row(
                row, search_fns, args.out_images,
                aspect=(aspect_w, aspect_h), max_edge=args.max_edge,
                jpeg_quality=args.jpeg_quality, min_width=args.min_width,
                min_height=args.min_height, candidates=args.candidates,
                primary=args.primary, fallback=fallback,
                use_japanese=not args.no_japanese,
                include_wikipedia=not args.no_wikipedia)
            for msg in row_errors:
                errors.append((row["date"], msg))
                print(f"  {row['date']} {row['kanji']}: {msg}", file=sys.stderr)
            if not row_out:
                missing.append((row["date"], row.get("gloss_en") or row["reading_en"]))
                continue
            out_rows.extend(row_out)
            print(f"  {row['date']} {row['kanji']}: {len(row_out)} candidate(s)")
        except Exception as e:  # one bad row must not discard the whole run
            errors.append((row["date"], repr(e)))
            print(f"  {row['date']} {row['kanji']}: ERROR {e}", file=sys.stderr)
            continue
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 scripts/content/fill/test_fetch_images.py`
Expected: `ALL PASS` (the new test plus all pre-existing tests — the refactor must not regress them).

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fetch_images.py scripts/content/fill/test_fetch_images.py
git commit -m "refactor(fill): extract fetch_candidates_for_row for reuse by generate"
```

---

### Task 5: `fill.py spine` — seed the store from the deterministic spine

**Files:**
- Create: `scripts/content/fill/fill.py`
- Test: `scripts/content/fill/test_fill.py`

**Interfaces:**
- Consumes: `store.connect/seed_days`; `assign_dates.season_starts/assign`; `assign_dates.SPINE_COLUMNS`.
- Produces:
  - `seed_from_pool(conn, pool, manifest, new_year_days=7, force=False) -> (seeded, skipped)` — runs `assign_dates.assign` and seeds the store.
  - `cmd_spine(args) -> int` and an `argparse` entrypoint `main(argv=None)` with a `spine` subparser (`--db`, `--pool`, `--manifest`, `--new-year-days`, `--force`).

Note: fetching the upstream pool stays the separate networked `fetch_spine.py` step (pinned SHA, rarely re-run). `spine` consumes the existing `spine_pool.json`.

- [ ] **Step 1: Write the failing test**

Create `scripts/content/fill/test_fill.py`:

```python
"""Offline checks for the fill.py CLI wrapper (spine/generate/compile).
No network — LLM and image providers are injected fakes. Matches the plain
test_* + __main__ runner convention.

Run directly:
    python3 scripts/content/fill/test_fill.py
"""
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fill  # noqa: E402
import store  # noqa: E402

FILL_DIR = Path(__file__).resolve().parent
REPO_ROOT = FILL_DIR.parents[2]


def _pool():
    # two words per Sekki season is plenty for the assigner's even_sample;
    # reuse the real bundled pool so placement stays representative.
    return json.loads((FILL_DIR / "spine_pool.json").read_text(encoding="utf-8"))


def _manifest():
    return json.loads((REPO_ROOT / "Resources" / "manifest.json").read_text(encoding="utf-8"))


def test_spine_seeds_365_days():
    conn = store.connect(":memory:")
    seeded, skipped = fill.seed_from_pool(conn, _pool(), _manifest())
    assert seeded == 365 and skipped == 0
    days = store.list_days(conn)
    assert len(days) == 365
    assert days[0]["date"] == "2026-01-01" and days[-1]["date"] == "2026-12-31"
    assert all(d["kanji"] for d in days)


def test_spine_respects_approve_freeze():
    conn = store.connect(":memory:")
    fill.seed_from_pool(conn, _pool(), _manifest())
    first = store.list_days(conn)[0]["date"]
    store.set_day_fields(conn, first, description_ja="人手による説明")
    store.set_approved(conn, first, True)
    seeded, skipped = fill.seed_from_pool(conn, _pool(), _manifest())
    assert skipped == 1
    assert store.get_day(conn, first)["description_ja"] == "人手による説明"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fill.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'fill'`.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/content/fill/fill.py`:

```python
#!/usr/bin/env python3
"""fill.py — the front door to the kigo-2026 content-fill workflow.

Four subcommands over the SQLite editorial review store (store.py):

    spine     seed the 365 day facts from the deterministic spine (assign_dates)
    generate  author prose + fetch image candidates for a date range
    compile   export approved days to content/kigo-2026.csv + run assemble.py
    review    serve the local web review UI

The proven stage scripts stay the engine; this orchestrates them and persists
to the store. "Approved freezes": spine/generate never touch an approved day
(unless --force). Stdlib only (+ Pillow, via fetch_images). See
docs/adr/0025-sqlite-editorial-review-store.md.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import assign_dates  # noqa: E402
import store  # noqa: E402

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
DEFAULT_DB = HERE / "review.db"
DEFAULT_POOL = HERE / "spine_pool.json"
DEFAULT_MANIFEST = REPO_ROOT / "Resources" / "manifest.json"


def seed_from_pool(conn, pool, manifest, new_year_days=7, force=False):
    starts = assign_dates.season_starts(manifest)
    records = assign_dates.assign(pool, starts, new_year_days)
    return store.seed_days(conn, records, force=force)


def cmd_spine(args):
    conn = store.connect(args.db)
    pool = json.loads(args.pool.read_text(encoding="utf-8"))
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    seeded, skipped = seed_from_pool(conn, pool, manifest, args.new_year_days, args.force)
    print(f"seeded {seeded} day(s); skipped {skipped} approved day(s)")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("spine", help="seed day facts from the deterministic spine")
    p.add_argument("--db", type=Path, default=DEFAULT_DB)
    p.add_argument("--pool", type=Path, default=DEFAULT_POOL)
    p.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    p.add_argument("--new-year-days", type=int, default=7, dest="new_year_days")
    p.add_argument("--force", action="store_true", help="overwrite approved days too")
    p.set_defaults(func=cmd_spine)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fill.py`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fill.py scripts/content/fill/test_fill.py
git commit -m "feat(fill): fill.py spine subcommand — seed store from deterministic spine"
```

---

### Task 6: `fill.py generate` — descriptions half

**Files:**
- Modify: `scripts/content/fill/fill.py`
- Test: `scripts/content/fill/test_fill.py`

**Interfaces:**
- Consumes: `store.list_days/set_day_fields`; `describe.PROMPT_PREAMBLE/_batch_payload/DATE_STAMP_RE`; `describe_via_claude.call_claude/extract_json_array`.
- Produces:
  - `generate_descriptions(conn, dates, call_llm, batch_size=20) -> (written:int, errors:list[str])` — builds the exact `describe.py` prompt for the given rows, calls `call_llm(prompt) -> text`, parses the JSON array, validates each row (`translation_en`/`description_ja`/`description_en` non-empty, no forbidden date stamp), and stores prose. `call_llm` is injectable (prod wires `describe_via_claude.call_claude` with the API key).
- `dates` is the list of **unapproved** day dicts to author (the caller filters).

- [ ] **Step 1: Write the failing test**

Append to `scripts/content/fill/test_fill.py`:

```python
def _seed_two(conn):
    rows = [{"date": "2026-03-25", "kanji": "桜", "reading_ja": "さくら",
             "reading_en": "sakura", "season": "spring", "subseason": "mid spring",
             "category": "plant", "gloss_en": "cherry blossom"},
            {"date": "2026-03-26", "kanji": "菫", "reading_ja": "すみれ",
             "reading_en": "sumire", "season": "spring", "subseason": "mid spring",
             "category": "plant", "gloss_en": "violet"}]
    store.seed_days(conn, rows)


def test_generate_descriptions_stores_prose():
    conn = store.connect(":memory:")
    _seed_two(conn)

    def fake_llm(prompt):
        # echo a valid JSON array for both dates in the prompt
        return json.dumps([
            {"date": "2026-03-25", "translation_en": "cherry-blossom viewing",
             "description_ja": "桜の説明。", "description_en": "Cherry blossoms mark spring."},
            {"date": "2026-03-26", "translation_en": "violet",
             "description_ja": "菫の説明。", "description_en": "Violets bloom in spring."},
        ], ensure_ascii=False)

    days = store.list_days(conn, status="unapproved")
    written, errors = fill.generate_descriptions(conn, days, fake_llm)
    assert written == 2 and errors == []
    d = store.get_day(conn, "2026-03-25")
    assert d["translation_en"] == "cherry-blossom viewing" and d["description_ja"] == "桜の説明。"


def test_generate_descriptions_rejects_empty_and_datestamp():
    conn = store.connect(":memory:")
    _seed_two(conn)

    def bad_llm(prompt):
        return json.dumps([
            {"date": "2026-03-25", "translation_en": "", "description_ja": "x", "description_en": "y"},
            {"date": "2026-03-26", "translation_en": "violet",
             "description_ja": "菫 (2026-03-26)", "description_en": "y"},
        ], ensure_ascii=False)

    days = store.list_days(conn, status="unapproved")
    written, errors = fill.generate_descriptions(conn, days, bad_llm)
    assert written == 0
    assert any("translation_en" in e for e in errors)
    assert any("date stamp" in e for e in errors)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fill.py`
Expected: FAIL — `AttributeError: module 'fill' has no attribute 'generate_descriptions'`.

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/content/fill/fill.py` (imports beside the others, then the function):

```python
# with the other imports:
import describe  # noqa: E402
import describe_via_claude  # noqa: E402
```

```python
def generate_descriptions(conn, dates, call_llm, batch_size=20):
    """Author prose for `dates` (day dicts) via call_llm(prompt)->text, validate,
    and store. Returns (written, errors). Nothing is written for a batch until
    its whole reply validates, mirroring describe.py's ingest gate."""
    written, errors = 0, []
    rows = [dict(d) for d in dates]
    for i in range(0, len(rows), batch_size):
        batch = rows[i:i + batch_size]
        payload = describe._batch_payload(batch)
        prompt = describe.PROMPT_PREAMBLE + json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
        try:
            arr = describe_via_claude.extract_json_array(call_llm(prompt))
        except (ValueError, json.JSONDecodeError) as e:
            errors.append(f"batch {i // batch_size}: reply did not parse: {e}")
            continue
        by_date = {obj.get("date"): obj for obj in arr}
        validated = []
        for row in batch:
            date = row["date"]
            obj = by_date.get(date, {})
            tr = (obj.get("translation_en") or "").strip()
            ja = (obj.get("description_ja") or "").strip()
            en = (obj.get("description_en") or "").strip()
            if not tr:
                errors.append(f"{date}: translation_en empty")
            if not ja:
                errors.append(f"{date}: description_ja empty")
            if not en:
                errors.append(f"{date}: description_en empty")
            if describe.DATE_STAMP_RE.search(ja + en):
                errors.append(f"{date}: description contains a forbidden date stamp")
            validated.append((date, tr, ja, en))
        if errors:
            continue
        for date, tr, ja, en in validated:
            store.set_day_fields(conn, date, translation_en=tr,
                                 description_ja=ja, description_en=en)
            written += 1
    return written, errors
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fill.py`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fill.py scripts/content/fill/test_fill.py
git commit -m "feat(fill): generate_descriptions — LLM-author prose into the store"
```

---

### Task 7: `fill.py generate` — images half + the `generate` subcommand

**Files:**
- Modify: `scripts/content/fill/fill.py`
- Test: `scripts/content/fill/test_fill.py`

**Interfaces:**
- Consumes: `store.clear_candidates/add_candidate/list_days`; `fetch_images.fetch_candidates_for_row` (Task 4); Task 6 `generate_descriptions`.
- Produces:
  - `generate_images(conn, dates, search_fns, out_images, *, download, wiki_lookup=None, **fetch_opts) -> (written:int, errors:list[str])` — for each day, `clear_candidates` then `fetch_candidates_for_row` and `add_candidate` each result. `written` counts candidate rows stored.
  - `cmd_generate(args) -> int` — resolves the range, selects **unapproved** days (unless `--force`, which also clears approval? No — `--force` includes approved days without unapproving them), runs descriptions (unless `--no-descriptions`) and images (unless `--no-images`). Wires the real `describe_via_claude.call_claude` (needs `ANTHROPIC_API_KEY`) and the real Pexels/Pixabay `search_fns` (needs provider keys) — errors clearly if a required key is missing.
  - `generate` subparser: `--db`, `--from`, `--to` (required), `--no-descriptions`, `--no-images`, `--force`, plus the image tuning flags passed through to `fetch_candidates_for_row` (`--candidates`, `--min-width`, `--min-height`, `--no-japanese`, `--no-wikipedia`, `--per-page`, `--sleep`, `--model`).

- [ ] **Step 1: Write the failing test**

Append to `scripts/content/fill/test_fill.py`:

```python
import fetch_images as fi  # noqa: E402


def test_generate_images_stores_candidates_and_clears_first():
    conn = store.connect(":memory:")
    _seed_two(conn)
    # a stale candidate that must be cleared before regenerating:
    store.add_candidate(conn, "2026-03-25", {"provider": "old", "out_file": "stale.jpg",
                                             "usable": "yes", "src_w": 10, "src_h": 10})

    def fake_search(term, lang):
        return [{"photo_id": f"{term}", "photographer": "Ansel",
                 "download_url": f"http://x/{term}", "source_url": "http://s",
                 "width": 1000, "height": 1500}]

    made = fi.Image.new("RGB", (1000, 1500), (90, 90, 90))
    with tempfile.TemporaryDirectory() as tmp:
        days = store.list_days(conn, status="unapproved")
        written, errors = fill.generate_images(
            conn, days, {"pexels": fake_search, "pixabay": fake_search}, Path(tmp),
            download=lambda url: made, wiki_lookup=lambda *a, **k: None,
            candidates=2, include_wikipedia=False)
        assert errors == []
        c = store.get_candidates(conn, "2026-03-25")
        assert len(c) == 2 and all(x["provider"] != "old" for x in c)
        assert (Path(tmp) / "kigo-03-25__c1.jpg").exists()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fill.py`
Expected: FAIL — `AttributeError: module 'fill' has no attribute 'generate_images'`.

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/content/fill/fill.py` (import `fetch_images` and `os`, then the functions):

```python
# with the other imports:
import functools  # noqa: E402
import os  # noqa: E402
import fetch_images  # noqa: E402
```

```python
def generate_images(conn, dates, search_fns, out_images, *, download,
                    wiki_lookup=None, include_wikipedia=True, **fetch_opts):
    """For each day: clear existing candidates, fetch fresh ones, store them.
    Returns (candidate rows written, errors). download/wiki_lookup injectable."""
    out_images.mkdir(parents=True, exist_ok=True)
    written, errors = 0, []
    wl = wiki_lookup or fetch_images._wikipedia_lookup
    for day in dates:
        row = {"date": day["date"], "kanji": day["kanji"],
               "gloss_en": day["gloss_en"], "reading_en": day["reading_en"]}
        store.clear_candidates(conn, day["date"])
        try:
            cand_rows, row_errors = fetch_images.fetch_candidates_for_row(
                row, search_fns, out_images, include_wikipedia=include_wikipedia,
                download=download, wiki_lookup=wl, **fetch_opts)
        except Exception as e:
            errors.append(f"{day['date']}: {e!r}")
            continue
        for msg in row_errors:
            errors.append(f"{day['date']}: {msg}")
        for cand in cand_rows:
            store.add_candidate(conn, day["date"], cand)
            written += 1
    return written, errors


def _select_days(conn, date_from, date_to, force):
    status = None if force else "unapproved"
    return store.list_days(conn, date_from, date_to, status=status)


def cmd_generate(args):
    conn = store.connect(args.db)
    days = _select_days(conn, args.date_from, args.date_to, args.force)
    if not days:
        print("no days to generate in range (all approved? run with --force)",
              file=sys.stderr)
        return 1

    if not args.no_descriptions:
        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if not api_key:
            print("error: set ANTHROPIC_API_KEY (or pass --no-descriptions)", file=sys.stderr)
            return 2
        call_llm = functools.partial(describe_via_claude.call_claude, api_key=api_key,
                                     model=args.model, max_tokens=8000)
        written, errors = generate_descriptions(conn, days, call_llm)
        print(f"descriptions: wrote {written} day(s)")
        for e in errors:
            print("  " + e, file=sys.stderr)

    if not args.no_images:
        fetch_images.load_dotenv()
        fallback = None if args.no_fallback else args.fallback
        providers = dict.fromkeys([args.primary] + ([fallback] if fallback else []))
        keys = fetch_images._resolve_keys(providers, None)
        if args.primary not in keys:
            print(f"error: primary provider {args.primary} has no key", file=sys.stderr)
            return 2
        search_fns = {prov: functools.partial(fetch_images._SEARCH[prov],
                                              api_key=keys[prov], per_page=args.per_page,
                                              sleep=args.sleep) for prov in keys}
        written, errors = generate_images(
            conn, days, search_fns, args.out_images,
            download=fetch_images._download_image,
            include_wikipedia=not args.no_wikipedia,
            candidates=args.candidates, min_width=args.min_width,
            min_height=args.min_height, primary=args.primary, fallback=fallback,
            use_japanese=not args.no_japanese)
        print(f"images: wrote {written} candidate row(s)")
        for e in errors[:10]:
            print("  " + e, file=sys.stderr)
    return 0
```

Add the `generate` subparser inside `main`, after the `spine` block:

```python
    g = sub.add_parser("generate", help="author prose + fetch image candidates for a range")
    g.add_argument("--db", type=Path, default=DEFAULT_DB)
    g.add_argument("--from", dest="date_from", required=True)
    g.add_argument("--to", dest="date_to", required=True)
    g.add_argument("--no-descriptions", action="store_true")
    g.add_argument("--no-images", action="store_true")
    g.add_argument("--force", action="store_true", help="include approved days too")
    g.add_argument("--out-images", type=Path, dest="out_images", default=HERE / "downloads")
    g.add_argument("--model", default=describe_via_claude.DEFAULT_MODEL)
    g.add_argument("--primary", choices=sorted(fetch_images.PROVIDERS), default="pexels")
    g.add_argument("--fallback", choices=sorted(fetch_images.PROVIDERS), default="pixabay")
    g.add_argument("--no-fallback", action="store_true")
    g.add_argument("--no-japanese", action="store_true")
    g.add_argument("--no-wikipedia", action="store_true")
    g.add_argument("--candidates", type=int, default=3)
    g.add_argument("--per-page", type=int, default=10, dest="per_page")
    g.add_argument("--min-width", type=int, default=800, dest="min_width")
    g.add_argument("--min-height", type=int, default=1200, dest="min_height")
    g.add_argument("--sleep", type=float, default=0.7)
    g.set_defaults(func=cmd_generate)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fill.py`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/fill.py scripts/content/fill/test_fill.py
git commit -m "feat(fill): generate images + the generate subcommand"
```

---

### Task 8: `fill.py compile` — export approved days + run assemble

**Files:**
- Modify: `scripts/content/fill/fill.py`
- Test: `scripts/content/fill/test_fill.py`

**Interfaces:**
- Consumes: `store.export_rows/pending_dates`; `build_csv.CONTRACT_COLUMNS`; `scripts/content/assemble.py` (subprocess).
- Produces:
  - `write_contract_csv(rows, out_csv, out_images) -> int` — copies each row's chosen JPEG (`out_images/<_out_file>` → `out_images/<image_id>.jpg`) and writes the exact 14-column CSV; returns row count.
  - `cmd_compile(args) -> int` — exports approved days in range, writes the CSV, reports pending dates on stderr, then runs `assemble.py`; returns non-zero if zero rows or if assemble fails.
  - `compile` subparser: `--db`, `--from`, `--to`, `--out-csv` (default `content/kigo-2026.csv`), `--out-images` (default `downloads`), `--manifest-out` (default `Resources/manifest.json`), `--image-base-url`.

- [ ] **Step 1: Write the failing test**

Append to `scripts/content/fill/test_fill.py`:

```python
import csv as _csv  # noqa: E402


def test_compile_writes_contract_csv_and_copies_image():
    import build_csv
    conn = store.connect(":memory:")
    _seed_two(conn)
    store.set_day_fields(conn, "2026-03-25", translation_en="cherry-blossom viewing",
                         description_ja="桜の説明。", description_en="Cherry blossoms.")
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "kigo-03-25__c1.jpg").write_bytes(b"jpegdata")
        cid = store.add_candidate(conn, "2026-03-25", {
            "provider": "pexels", "photographer": "Ansel", "title_ja": "桜",
            "title_en": "cherry blossom", "license_ja": "Pexels ライセンス",
            "license_en": "Pexels License", "out_file": "kigo-03-25__c1.jpg", "usable": "yes"})
        store.set_chosen(conn, "2026-03-25", cid)
        store.set_approved(conn, "2026-03-25", True)

        out_csv = tmp / "kigo-2026.csv"
        rows = store.export_rows(conn)
        n = fill.write_contract_csv(rows, out_csv, tmp)
        assert n == 1
        assert (tmp / "kigo-03-25.jpg").read_bytes() == b"jpegdata"
        with out_csv.open(encoding="utf-8") as f:
            reader = _csv.DictReader(f)
            assert list(reader.fieldnames) == list(build_csv.CONTRACT_COLUMNS)
            row = next(reader)
            assert row["image_id"] == "kigo-03-25"
            assert row["attribution_credit_en"] == "Photo: Ansel / Pexels"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_fill.py`
Expected: FAIL — `AttributeError: module 'fill' has no attribute 'write_contract_csv'`.

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/content/fill/fill.py` (imports + functions):

```python
# with the other imports:
import csv  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
import build_csv  # noqa: E402
```

```python
def write_contract_csv(rows, out_csv, out_images):
    """Copy each chosen JPEG to its canonical <image_id>.jpg and write the exact
    14-column contract CSV build_csv/csv_parser expect. Returns row count."""
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    for r in rows:
        src = out_images / r["_out_file"]
        dest = out_images / f"{r['image_id']}.jpg"
        if src.resolve() != dest.resolve():
            shutil.copyfile(src, dest)
    with out_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=build_csv.CONTRACT_COLUMNS)
        writer.writeheader()
        for r in rows:
            writer.writerow({c: r[c] for c in build_csv.CONTRACT_COLUMNS})
    return len(rows)


def cmd_compile(args):
    conn = store.connect(args.db)
    rows = store.export_rows(conn, args.date_from, args.date_to)
    if not rows:
        print("error: no approved days with a chosen image in range", file=sys.stderr)
        return 1
    n = write_contract_csv(rows, args.out_csv, args.out_images)
    print(f"wrote {n} approved row(s) to {args.out_csv}")
    pending = store.pending_dates(conn, args.date_from, args.date_to)
    if pending:
        print(f"  skipped {len(pending)} unapproved/incomplete day(s) in range", file=sys.stderr)

    assemble = REPO_ROOT / "scripts" / "content" / "assemble.py"
    cmd = [sys.executable, str(assemble), "--csv", str(args.out_csv),
           "--out", str(args.manifest_out)]
    if args.image_base_url:
        cmd += ["--image-base-url", args.image_base_url]
    result = subprocess.run(cmd)
    return result.returncode
```

Add the `compile` subparser inside `main`, after the `generate` block:

```python
    c = sub.add_parser("compile", help="export approved days + run assemble.py")
    c.add_argument("--db", type=Path, default=DEFAULT_DB)
    c.add_argument("--from", dest="date_from", default=None)
    c.add_argument("--to", dest="date_to", default=None)
    c.add_argument("--out-csv", type=Path, dest="out_csv",
                   default=REPO_ROOT / "content" / "kigo-2026.csv")
    c.add_argument("--out-images", type=Path, dest="out_images", default=HERE / "downloads")
    c.add_argument("--manifest-out", type=Path, dest="manifest_out",
                   default=REPO_ROOT / "Resources" / "manifest.json")
    c.add_argument("--image-base-url", dest="image_base_url", default=None)
    c.set_defaults(func=cmd_compile)
```

`assemble.py`'s flag is confirmed `--image-base-url` (assemble.py:45, `dest="image_base_url"`) — the wiring above matches it exactly.

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_fill.py`
Expected: `ALL PASS`.

- [ ] **Step 5: End-to-end gate check (manual, one-time)**

Build a tiny approved DB and confirm the real `assemble.py` accepts the output:

Run:
```bash
python3 - <<'PY'
import sys; sys.path.insert(0, "scripts/content/fill")
import store, fill
conn = store.connect("/tmp/fill-e2e.db")
# ... (reuse test_compile setup) ...
PY
python3 scripts/content/fill/fill.py compile --db /tmp/fill-e2e.db \
  --out-csv /tmp/kigo-e2e.csv --out-images scripts/content/fill/downloads \
  --manifest-out /tmp/manifest-e2e.json
```
Expected: `assemble.py` exits 0 and writes the manifest (proves the contract column set + values are accepted by the untouched gate).

- [ ] **Step 6: Commit**

```bash
git add scripts/content/fill/fill.py scripts/content/fill/test_fill.py
git commit -m "feat(fill): compile subcommand — export approved days + run assemble"
```

---

### Task 9: `webapp.py` — pure request handlers over the store

**Files:**
- Create: `scripts/content/fill/webapp.py`
- Test: `scripts/content/fill/test_webapp.py`

**Interfaces:**
- Consumes: `store` accessors.
- Produces:
  - `day_summary(day, candidate_count) -> dict` — `{date, kanji, approved, has_prose, has_image}`; `has_prose = bool(translation_en and description_ja and description_en)`; `has_image = day["chosen_candidate_id"] is not None`.
  - `handle_list_days(conn, date_from, date_to, status) -> list[dict]`
  - `handle_get_day(conn, date) -> dict | None` — day fields + `"candidates": [candidate dicts]`.
  - `handle_patch_day(conn, date, body) -> dict` — whitelists `reading_ja, reading_en, translation_en, description_ja, description_en` → `set_day_fields`; `chosen_candidate_id` → `set_chosen`; `approved` → `set_approved`. Raises `ValueError` (→ HTTP 400) on unknown key, unknown date, or invalid chosen candidate. Returns the updated `handle_get_day`.

- [ ] **Step 1: Write the failing test**

Create `scripts/content/fill/test_webapp.py`:

```python
"""Offline checks for the review web API's pure handlers
(scripts/content/fill/webapp.py). No socket, no browser.

Run directly:
    python3 scripts/content/fill/test_webapp.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store  # noqa: E402
import webapp  # noqa: E402


def _mem():
    conn = store.connect(":memory:")
    store.seed_days(conn, [{"date": "2026-03-25", "kanji": "桜", "reading_ja": "さくら",
                            "reading_en": "sakura", "season": "spring",
                            "subseason": "mid spring", "category": "plant",
                            "gloss_en": "cherry blossom"}])
    return conn


def _cand(usable="yes"):
    return {"provider": "pexels", "photographer": "Ansel", "title_ja": "桜",
            "title_en": "cherry blossom", "license_ja": "Pexels ライセンス",
            "license_en": "Pexels License", "out_file": "kigo-03-25__c1.jpg",
            "usable": usable, "src_w": 1000, "src_h": 1500}


def test_day_summary_flags():
    conn = _mem()
    day = store.get_day(conn, "2026-03-25")
    s = webapp.day_summary(day, 0)
    assert s == {"date": "2026-03-25", "kanji": "桜", "approved": 0,
                 "has_prose": False, "has_image": False}


def test_get_day_includes_candidates():
    conn = _mem()
    store.add_candidate(conn, "2026-03-25", _cand())
    day = webapp.handle_get_day(conn, "2026-03-25")
    assert day["kanji"] == "桜" and len(day["candidates"]) == 1
    assert webapp.handle_get_day(conn, "2026-01-01") is None


def test_patch_day_edits_prose_and_approves():
    conn = _mem()
    cid = store.add_candidate(conn, "2026-03-25", _cand())
    updated = webapp.handle_patch_day(conn, "2026-03-25", {
        "description_ja": "手直し", "chosen_candidate_id": cid, "approved": True})
    assert updated["description_ja"] == "手直し"
    assert updated["chosen_candidate_id"] == cid and updated["approved"] == 1


def test_patch_day_rejects_bad_input():
    conn = _mem()
    ref = store.add_candidate(conn, "2026-03-25", _cand(usable="no"))
    for body in ({"nonsense": 1}, {"chosen_candidate_id": ref}, {"chosen_candidate_id": 9999}):
        try:
            webapp.handle_patch_day(conn, "2026-03-25", body)
        except ValueError:
            continue
        raise AssertionError(f"handle_patch_day should reject {body}")


if __name__ == "__main__":
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print("ALL PASS")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_webapp.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'webapp'`.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/content/fill/webapp.py`:

```python
#!/usr/bin/env python3
"""webapp.py — the local review web API for the kigo-2026 fill workflow.

Pure request handlers over store.py (unit-testable without a socket) plus a thin
http.server adapter (wired by `fill.py review`). The single per-day review
surface: edit readings/prose, pick the image, approve the day. Stdlib only.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store  # noqa: E402

_PROSE_FIELDS = ("reading_ja", "reading_en", "translation_en",
                 "description_ja", "description_en")


def day_summary(day, candidate_count):
    return {
        "date": day["date"], "kanji": day["kanji"], "approved": day["approved"],
        "has_prose": bool(day["translation_en"] and day["description_ja"]
                          and day["description_en"]),
        "has_image": day["chosen_candidate_id"] is not None,
    }


def handle_list_days(conn, date_from=None, date_to=None, status=None):
    out = []
    for day in store.list_days(conn, date_from, date_to, status):
        count = len(store.get_candidates(conn, day["date"]))
        out.append(day_summary(day, count))
    return out


def handle_get_day(conn, date):
    day = store.get_day(conn, date)
    if day is None:
        return None
    day["candidates"] = store.get_candidates(conn, date)
    return day


def handle_patch_day(conn, date, body):
    if store.get_day(conn, date) is None:
        raise ValueError(f"unknown date {date}")
    known = set(_PROSE_FIELDS) | {"chosen_candidate_id", "approved"}
    bad = set(body) - known
    if bad:
        raise ValueError(f"unknown fields: {sorted(bad)}")
    prose = {k: body[k] for k in _PROSE_FIELDS if k in body}
    if prose:
        store.set_day_fields(conn, date, **prose)
    if "chosen_candidate_id" in body:
        store.set_chosen(conn, date, body["chosen_candidate_id"])
    if "approved" in body:
        store.set_approved(conn, date, bool(body["approved"]))
    return handle_get_day(conn, date)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/content/fill/test_webapp.py`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/content/fill/webapp.py scripts/content/fill/test_webapp.py
git commit -m "feat(fill): review web API — pure per-day handlers over the store"
```

---

### Task 10: `fill.py review` — HTTP adapter + vanilla-JS SPA

**Files:**
- Modify: `scripts/content/fill/webapp.py` (add `make_server`), `scripts/content/fill/fill.py` (add `cmd_review` + subparser)
- Create: `scripts/content/fill/web/index.html`, `web/app.js`, `web/style.css`
- Test: `scripts/content/fill/test_webapp.py`

**Interfaces:**
- Consumes: Task 9 handlers; `store.connect`; the JPEGs under the `downloads/` dir.
- Produces:
  - `make_server(conn, web_dir, images_dir, host="127.0.0.1", port=8000) -> http.server.HTTPServer` — routes: `GET /` and static `web/*`; `GET /api/days?from&to&status`; `GET /api/days/<date>`; `PATCH /api/days/<date>` (JSON body); `GET /candidates/<file>` (served from `images_dir`, `.jpg` only). Returns JSON with correct status codes (`400` on `ValueError`, `404` on unknown/None).
  - `cmd_review(args)` + `review` subparser (`--db`, `--port`, `--images`).

- [ ] **Step 1: Write the failing test**

Append to `scripts/content/fill/test_webapp.py` (before the `__main__` runner):

```python
import json as _json  # noqa: E402
import threading  # noqa: E402
import urllib.request  # noqa: E402
import urllib.error  # noqa: E402


def test_make_server_serves_api_over_http():
    conn = _mem()
    store.add_candidate(conn, "2026-03-25", _cand())
    web_dir = Path(__file__).resolve().parent / "web"
    srv = webapp.make_server(conn, web_dir, Path("/tmp"), port=0)
    port = srv.server_address[1]
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    try:
        base = f"http://127.0.0.1:{port}"
        days = _json.loads(urllib.request.urlopen(base + "/api/days").read())
        assert days[0]["date"] == "2026-03-25"
        one = _json.loads(urllib.request.urlopen(base + "/api/days/2026-03-25").read())
        assert len(one["candidates"]) == 1
        try:
            urllib.request.urlopen(base + "/api/days/2026-01-01")
        except urllib.error.HTTPError as e:
            assert e.code == 404
        else:
            raise AssertionError("expected 404 for unknown date")
        # index.html is served at /
        assert b"<" in urllib.request.urlopen(base + "/").read()
    finally:
        srv.shutdown()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/content/fill/test_webapp.py`
Expected: FAIL — `AttributeError: module 'webapp' has no attribute 'make_server'` (and `web/index.html` does not yet exist).

- [ ] **Step 3: Write the frontend files**

Create `scripts/content/fill/web/index.html`:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>kigo review</title>
  <link rel="stylesheet" href="/style.css">
</head>
<body>
  <header>
    <h1>kigo-2026 review</h1>
    <div class="filters">
      <input id="from" placeholder="from YYYY-MM-DD">
      <input id="to" placeholder="to YYYY-MM-DD">
      <select id="status">
        <option value="">all</option>
        <option value="unapproved">unapproved</option>
        <option value="approved">approved</option>
      </select>
      <button id="reload">reload</button>
    </div>
  </header>
  <main>
    <ul id="days"></ul>
    <section id="editor" hidden></section>
  </main>
  <script src="/app.js"></script>
</body>
</html>
```

Create `scripts/content/fill/web/style.css`:

```css
* { box-sizing: border-box; }
body { font-family: system-ui, sans-serif; margin: 0; color: #222; }
header { padding: 1rem; border-bottom: 1px solid #ddd; }
.filters { display: flex; gap: .5rem; margin-top: .5rem; flex-wrap: wrap; }
main { display: flex; gap: 1rem; padding: 1rem; align-items: flex-start; }
#days { list-style: none; margin: 0; padding: 0; width: 22rem; max-height: 80vh; overflow: auto; }
#days li { padding: .5rem; border: 1px solid #eee; cursor: pointer; display: flex; justify-content: space-between; }
#days li.approved { background: #eaf7ea; }
#days li .marks { color: #999; font-size: .8rem; }
#editor { flex: 1; }
#editor label { display: block; margin: .6rem 0 .2rem; font-weight: 600; }
#editor input[type=text], #editor textarea { width: 100%; padding: .4rem; }
#editor textarea { min-height: 4rem; }
.candidates { display: flex; gap: .5rem; flex-wrap: wrap; }
.candidates figure { margin: 0; width: 8rem; }
.candidates img { width: 100%; border: 3px solid transparent; }
.candidates input:checked + img { border-color: #2a7; }
.candidates figcaption { font-size: .75rem; color: #666; }
.candidates .refonly { opacity: .5; }
.bar { margin-top: 1rem; display: flex; gap: 1rem; align-items: center; }
```

Create `scripts/content/fill/web/app.js`:

```javascript
const $ = (sel) => document.querySelector(sel);

async function loadDays() {
  const params = new URLSearchParams();
  if ($("#from").value) params.set("from", $("#from").value);
  if ($("#to").value) params.set("to", $("#to").value);
  if ($("#status").value) params.set("status", $("#status").value);
  const days = await (await fetch("/api/days?" + params)).json();
  const ul = $("#days");
  ul.innerHTML = "";
  for (const d of days) {
    const li = document.createElement("li");
    if (d.approved) li.classList.add("approved");
    const marks = `${d.has_prose ? "✍" : "·"}${d.has_image ? "🖼" : "·"}${d.approved ? "✓" : ""}`;
    li.innerHTML = `<span>${d.date} ${d.kanji}</span><span class="marks">${marks}</span>`;
    li.onclick = () => loadEditor(d.date);
    ul.appendChild(li);
  }
}

async function loadEditor(date) {
  const day = await (await fetch("/api/days/" + date)).json();
  const ed = $("#editor");
  ed.hidden = false;
  const field = (label, key, tag = "input") =>
    `<label>${label}</label>${tag === "textarea"
      ? `<textarea data-key="${key}">${day[key] || ""}</textarea>`
      : `<input type="text" data-key="${key}" value="${(day[key] || "").replace(/"/g, "&quot;")}">`}`;
  const cands = day.candidates.map((c) => {
    const ref = (c.usable || "").toLowerCase() === "no";
    return `<figure class="${ref ? "refonly" : ""}">
      <label><input type="radio" name="chosen" value="${c.id}"
        ${day.chosen_candidate_id === c.id ? "checked" : ""} ${ref ? "disabled" : ""}>
      <img src="/candidates/${c.out_file}" alt=""></label>
      <figcaption>${c.provider} · ${c.photographer}${ref ? " · ref-only" : ""}</figcaption>
    </figure>`;
  }).join("");
  ed.innerHTML = `<h2>${day.date} ${day.kanji} (${day.reading_ja})</h2>
    ${field("reading_ja", "reading_ja")}
    ${field("reading_en", "reading_en")}
    ${field("translation_en", "translation_en")}
    ${field("description_ja", "description_ja", "textarea")}
    ${field("description_en", "description_en", "textarea")}
    <label>image candidates</label>
    <div class="candidates">${cands || "<em>none — run generate</em>"}</div>
    <div class="bar">
      <label><input type="checkbox" id="approved" ${day.approved ? "checked" : ""}> approved</label>
      <button id="save">save</button><span id="msg"></span>
    </div>`;
  $("#save").onclick = () => saveEditor(date);
}

async function saveEditor(date) {
  const body = {};
  for (const el of document.querySelectorAll("#editor [data-key]")) body[el.dataset.key] = el.value;
  const chosen = document.querySelector('input[name="chosen"]:checked');
  if (chosen) body.chosen_candidate_id = Number(chosen.value);
  body.approved = $("#approved").checked;
  const res = await fetch("/api/days/" + date, {
    method: "PATCH", headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  $("#msg").textContent = res.ok ? "saved" : "error: " + (await res.text());
  if (res.ok) loadDays();
}

$("#reload").onclick = loadDays;
loadDays();
```

- [ ] **Step 4: Add `make_server` to `webapp.py`**

Append to `scripts/content/fill/webapp.py`:

```python
import http.server  # noqa: E402
import urllib.parse  # noqa: E402


def make_server(conn, web_dir, images_dir, host="127.0.0.1", port=8000):
    web_dir, images_dir = Path(web_dir), Path(images_dir)

    class Handler(http.server.BaseHTTPRequestHandler):
        def _send(self, code, body, ctype="application/json"):
            payload = json.dumps(body).encode("utf-8") if ctype == "application/json" else body
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def _static(self, name):
            path = (web_dir / name).resolve()
            if web_dir.resolve() not in path.parents or not path.is_file():
                return self._send(404, {"error": "not found"})
            ctype = {"html": "text/html", "js": "application/javascript",
                     "css": "text/css"}.get(path.suffix.lstrip("."), "text/plain")
            self._send(200, path.read_bytes(), ctype + "; charset=utf-8")

        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            parts = [p for p in parsed.path.split("/") if p]
            if not parts:
                return self._static("index.html")
            if parts[0] in ("app.js", "style.css", "index.html"):
                return self._static(parts[0])
            if parts[:1] == ["api"] and parts[1:2] == ["days"]:
                if len(parts) == 2:
                    q = urllib.parse.parse_qs(parsed.query)
                    return self._send(200, handle_list_days(
                        conn, q.get("from", [None])[0], q.get("to", [None])[0],
                        q.get("status", [None])[0]))
                day = handle_get_day(conn, parts[2])
                return self._send(404 if day is None else 200,
                                  {"error": "unknown date"} if day is None else day)
            if parts[:1] == ["candidates"] and len(parts) == 2 and parts[1].endswith(".jpg"):
                path = (images_dir / parts[1]).resolve()
                if images_dir.resolve() not in path.parents or not path.is_file():
                    return self._send(404, {"error": "not found"})
                return self._send(200, path.read_bytes(), "image/jpeg")
            return self._send(404, {"error": "not found"})

        def do_PATCH(self):
            parsed = urllib.parse.urlparse(self.path)
            parts = [p for p in parsed.path.split("/") if p]
            if parts[:2] != ["api", "days"] or len(parts) != 3:
                return self._send(404, {"error": "not found"})
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
            try:
                return self._send(200, handle_patch_day(conn, parts[2], body))
            except ValueError as e:
                return self._send(400, {"error": str(e)})

        def log_message(self, *a):  # keep the console quiet
            pass

    return http.server.HTTPServer((host, port), Handler)
```

- [ ] **Step 5: Wire `cmd_review` into `fill.py`**

Add to `scripts/content/fill/fill.py` (import + command + subparser):

```python
# with the other imports:
import webapp  # noqa: E402
```

```python
def cmd_review(args):
    conn = store.connect(args.db)
    srv = webapp.make_server(conn, HERE / "web", args.images, port=args.port)
    host, port = srv.server_address
    print(f"review UI on http://{host}:{port}  (Ctrl-C to stop)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    return 0
```

Add the `review` subparser inside `main`, after the `compile` block:

```python
    r = sub.add_parser("review", help="serve the local web review UI")
    r.add_argument("--db", type=Path, default=DEFAULT_DB)
    r.add_argument("--port", type=int, default=8000)
    r.add_argument("--images", type=Path, default=HERE / "downloads")
    r.set_defaults(func=cmd_review)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `python3 scripts/content/fill/test_webapp.py`
Expected: `ALL PASS`.

- [ ] **Step 7: Manual UI smoke check (one-time)**

Run: `python3 scripts/content/fill/fill.py review --db /tmp/fill-e2e.db --port 8765`
Then open `http://127.0.0.1:8765`. Confirm: day list renders with prose/image/approve marks; clicking a day loads the editor; candidate thumbnails show and a reference-only candidate's radio is disabled; editing prose + picking an image + ticking approved + Save persists (the list marks update). Ctrl-C to stop.

- [ ] **Step 8: Commit**

```bash
git add scripts/content/fill/webapp.py scripts/content/fill/fill.py scripts/content/fill/web scripts/content/fill/test_webapp.py
git commit -m "feat(fill): review subcommand — http.server adapter + vanilla-JS SPA"
```

---

### Task 11: Docs — README front door + ADR + gitignore

**Files:**
- Modify: `scripts/content/fill/README.md`, `scripts/content/fill/.gitignore`
- Create: `docs/adr/0025-sqlite-editorial-review-store.md`

**Interfaces:**
- Consumes: everything above. No code; documentation + ignore rule.

- [ ] **Step 1: Ignore the DB**

Add to `scripts/content/fill/.gitignore`:

```
review.db
review.db-wal
review.db-shm
```

- [ ] **Step 2: Write the ADR**

Create `docs/adr/0025-sqlite-editorial-review-store.md`:

```markdown
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
```

- [ ] **Step 3: Update the README front door**

In `scripts/content/fill/README.md`, add a section near the top (after the pipeline diagram) documenting the new wrapper as the recommended path, keeping the legacy per-stage docs below it:

````markdown
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
````

- [ ] **Step 4: Verify docs reference real behavior**

Run: `python3 scripts/content/fill/fill.py --help` and each `... <cmd> --help`
Expected: the four subcommands and the flags named in the README all exist (no drift between docs and `argparse`).

- [ ] **Step 5: Run the full fill test suite once**

Run:
```bash
for t in test_store test_fill test_webapp test_fetch_images; do
  echo "== $t =="; python3 scripts/content/fill/$t.py || exit 1
done
python3 scripts/content/test_pipeline.py
```
Expected: `ALL PASS` from each fill suite and the existing pipeline suite (nothing regressed).

- [ ] **Step 6: Commit**

```bash
git add scripts/content/fill/README.md scripts/content/fill/.gitignore docs/adr/0025-sqlite-editorial-review-store.md
git commit -m "docs(fill): README wrapper front door + ADR 0025 (SQLite review store)"
```

---

## Self-Review

**1. Spec coverage** — every spec section maps to a task:
- SQLite store (schema, two lifecycles) → Tasks 1–3.
- Approved-freezes rule → Task 1 (`seed_days` skip), Task 7 (`_select_days`).
- CLI `spine`/`generate`/`compile`/`review` → Tasks 5, 6+7, 8, 10.
- Reuse vs. refactor (assign_dates, describe*, fetch_images extract, build_csv contract, assemble untouched) → Tasks 4, 5, 6, 8.
- Unified per-day web gate, stdlib server + vanilla JS → Tasks 9–10.
- Compile partial semantics → Task 8 (`export_rows`/`pending_dates`).
- Testing + error handling → tests in every task; key/`--placeholder`/zero-approved errors in Tasks 7–8.
- Non-goals (image re-hosting post-compile via `--image-base-url`; no auth) → Task 8 flag, Task 10 localhost bind.

**2. Placeholder scan** — no TBD/TODO; every code step shows complete code.

**3. Type consistency** — `store.export_rows` emits the private `_out_file` consumed by `fill.write_contract_csv`; `add_candidate` reads only `CANDIDATE_STORE_COLUMNS` (ignoring `candidate`/`chosen`/`image_id` that `candidate_row` also emits); `handle_patch_day` field whitelist matches `store.set_day_fields`'s writable set plus `chosen_candidate_id`/`approved`; contract columns reference the single source `build_csv.CONTRACT_COLUMNS` everywhere.

**Verified during planning:** `assemble.py`'s flag is `--image-base-url` (assemble.py:45) — `cmd_compile` matches it. Contract columns, the candidate schema, and the stdlib test convention were all read from the live scripts, not assumed.
```
