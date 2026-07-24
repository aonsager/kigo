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


def test_day_summary_flags():
    conn = _mem()
    day = store.get_day(conn, "2026-03-25")
    s = webapp.day_summary(day)
    assert s == {"date": "2026-03-25", "kanji": "桜", "approved": 0,
                 "reading_ja": "さくら", "season": "spring",
                 "subseason": "mid spring", "has_prose": False}


def test_patch_day_edits_prose_and_approves():
    conn = _mem()
    updated = webapp.handle_patch_day(conn, "2026-03-25", {
        "description_ja": "手直し", "approved": True})
    assert updated["description_ja"] == "手直し"
    assert updated["approved"] == 1


def test_patch_day_rejects_bad_input():
    conn = _mem()
    for body in ({"nonsense": 1},):
        try:
            webapp.handle_patch_day(conn, "2026-03-25", body)
        except ValueError:
            continue
        raise AssertionError(f"handle_patch_day should reject {body}")


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


import json as _json  # noqa: E402
import threading  # noqa: E402
import urllib.request  # noqa: E402
import urllib.error  # noqa: E402


def test_make_server_serves_api_over_http():
    conn = _mem()
    web_dir = Path(__file__).resolve().parent / "web"
    srv = webapp.make_server(conn, web_dir, port=0)
    port = srv.server_address[1]
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    try:
        base = f"http://127.0.0.1:{port}"
        days = _json.loads(urllib.request.urlopen(base + "/api/days").read())
        assert days[0]["date"] == "2026-03-25"
        one = _json.loads(urllib.request.urlopen(base + "/api/days/2026-03-25").read())
        assert one["kanji"] == "桜"
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


if __name__ == "__main__":
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print("ALL PASS")
