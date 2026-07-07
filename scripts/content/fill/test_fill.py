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


if __name__ == "__main__":
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print("ALL PASS")
