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
