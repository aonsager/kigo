"""Offline checks for the SQLite editorial review store
(scripts/content/fill/store.py). No network, no simulator. Matches the plain
test_* + __main__ runner convention of test_fetch_images.py.

Run directly:
    python3 scripts/content/fill/test_store.py
"""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store  # noqa: E402
import build_csv  # noqa: E402


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
    assert day["approved"] == 0


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


def test_migration_drops_candidates_and_preserves_days():
    # Build a pre-migration (v0) DB by hand: old days schema with
    # chosen_candidate_id + a candidates table + real editorial data.
    import sqlite3
    tmp_dir = Path(tempfile.mkdtemp())
    p = tmp_dir / "old.db"
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


def test_export_rows_gates_on_prose_completeness():
    conn = _mem()
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


def test_export_rows_excludes_leftover_date_stamp():
    # Regression: _is_complete previously checked only non-emptiness, so an
    # approved day whose prose still carried a leftover date-stamp (something
    # assemble.py/validator.py reject) passed export_rows, landed in the CSV,
    # and only then failed assemble.py downstream. The gate must catch it here.
    conn = _mem()
    store.seed_days(conn, [_fact_row(date="2026-01-01", kanji="正月")])
    store.set_day_fields(conn, "2026-01-01", translation_en="New Year",
                         description_ja="説明 (2026-01-01)", description_en="Description")
    store.set_approved(conn, "2026-01-01", True)
    assert store.export_rows(conn) == []  # every field non-empty, but date-stamped
    # Stripping the stamp makes the same day exportable again.
    store.set_day_fields(conn, "2026-01-01", description_ja="説明")
    rows = store.export_rows(conn)
    assert len(rows) == 1 and rows[0]["kanji"] == "正月"


def test_rebuild_days_dropping_chosen_is_rerunnable():
    # Direct check on the SQLite < 3.35 fallback helper: calling it twice in a
    # row (simulating a re-run after a crash left a stale `days_new` behind)
    # must not raise (e.g. a PRIMARY KEY conflict from a leftover days_new)
    # and must preserve the real data.
    import sqlite3
    conn = sqlite3.connect(":memory:")
    conn.executescript("""
        CREATE TABLE days (date TEXT PRIMARY KEY, kanji TEXT DEFAULT '',
            reading_ja TEXT DEFAULT '', reading_en TEXT DEFAULT '',
            season TEXT DEFAULT '', subseason TEXT DEFAULT '', category TEXT DEFAULT '',
            gloss_en TEXT DEFAULT '', translation_en TEXT DEFAULT '',
            description_ja TEXT DEFAULT '', description_en TEXT DEFAULT '',
            chosen_candidate_id INTEGER, approved INTEGER DEFAULT 0,
            created_at TEXT DEFAULT '', updated_at TEXT DEFAULT '');
        INSERT INTO days (date, kanji, description_ja, approved)
            VALUES ('2026-07-07', '七夕', '和文', 1);
    """)
    conn.commit()
    store._rebuild_days_dropping_chosen(conn)
    row = conn.execute("SELECT kanji, description_ja, approved FROM days WHERE date = ?",
                        ("2026-07-07",)).fetchone()
    assert row == ("七夕", "和文", 1)
    # Re-run on the same, already-rebuilt table — must not error or duplicate.
    store._rebuild_days_dropping_chosen(conn)
    row2 = conn.execute("SELECT kanji, description_ja, approved FROM days WHERE date = ?",
                         ("2026-07-07",)).fetchone()
    assert row2 == ("七夕", "和文", 1)
    assert conn.execute("SELECT COUNT(*) FROM days").fetchone()[0] == 1


def test_migration_fallback_survives_leftover_days_new():
    # End-to-end via connect(): force the pre-3.35 fallback path regardless of
    # the real local sqlite version, with a fully-formed but stale `days_new`
    # already present (as a crash between CREATE/INSERT and DROP/RENAME would
    # leave behind) — including a row for the same date, so an unguarded
    # INSERT INTO days_new ... SELECT ... FROM days would hit a PRIMARY KEY
    # conflict without the `DROP TABLE IF EXISTS days_new` fix.
    import sqlite3
    tmp_dir = Path(tempfile.mkdtemp())
    p = tmp_dir / "fallback.db"
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
            VALUES ('2026-05-05', '端午', '和文の説明', 1, 3);
        CREATE TABLE days_new (date TEXT PRIMARY KEY, kanji TEXT NOT NULL DEFAULT '',
            reading_ja TEXT NOT NULL DEFAULT '', reading_en TEXT NOT NULL DEFAULT '',
            season TEXT NOT NULL DEFAULT '', subseason TEXT NOT NULL DEFAULT '',
            category TEXT NOT NULL DEFAULT '', gloss_en TEXT NOT NULL DEFAULT '',
            translation_en TEXT NOT NULL DEFAULT '', description_ja TEXT NOT NULL DEFAULT '',
            description_en TEXT NOT NULL DEFAULT '', approved INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '');
        INSERT INTO days_new (date, kanji, approved) VALUES ('2026-05-05', 'stale-partial', 0);
    """)
    c.execute("PRAGMA user_version = 0")
    c.commit(); c.close()

    orig = sqlite3.sqlite_version_info
    sqlite3.sqlite_version_info = (3, 34, 0)  # force the pre-3.35 fallback branch
    try:
        conn = store.connect(p)  # must not raise despite the leftover days_new
    finally:
        sqlite3.sqlite_version_info = orig

    day = store.get_day(conn, "2026-05-05")
    assert day["kanji"] == "端午" and day["description_ja"] == "和文の説明" and day["approved"] == 1
    cols = {r[1] for r in conn.execute("PRAGMA table_info(days)")}
    assert "chosen_candidate_id" not in cols
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert "days_new" not in tables and "candidates" not in tables
    assert conn.execute("PRAGMA user_version").fetchone()[0] == store._SCHEMA_VERSION


if __name__ == "__main__":
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print("ALL PASS")
