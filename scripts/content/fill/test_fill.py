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


if __name__ == "__main__":
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print("ALL PASS")
