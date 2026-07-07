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
import fetch_images as fi  # noqa: E402

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


def test_generate_descriptions_bad_batch_does_not_poison_later_batch():
    conn = store.connect(":memory:")
    _seed_two(conn)  # 2026-03-25, 2026-03-26

    def mixed_llm(prompt):
        # each single-date batch echoes just its own row; 03-25 is invalid (empty
        # translation_en), 03-26 is valid — proves a bad earlier batch must not
        # suppress a valid later one.
        if "2026-03-25" in prompt:
            return json.dumps([{"date": "2026-03-25", "translation_en": "",
                                "description_ja": "x", "description_en": "y"}], ensure_ascii=False)
        return json.dumps([{"date": "2026-03-26", "translation_en": "violet",
                            "description_ja": "菫の説明。", "description_en": "Violets bloom."}],
                          ensure_ascii=False)

    days = store.list_days(conn, status="unapproved")
    written, errors = fill.generate_descriptions(conn, days, mixed_llm, batch_size=1)
    assert written == 1
    assert store.get_day(conn, "2026-03-26")["translation_en"] == "violet"
    assert store.get_day(conn, "2026-03-25")["translation_en"] == ""  # bad batch wrote nothing
    assert any("2026-03-25" in e for e in errors)


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


if __name__ == "__main__":
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print("ALL PASS")
