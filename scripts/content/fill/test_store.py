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


if __name__ == "__main__":
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print("ALL PASS")
