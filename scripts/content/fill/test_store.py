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


if __name__ == "__main__":
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print("ALL PASS")
