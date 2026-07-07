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
