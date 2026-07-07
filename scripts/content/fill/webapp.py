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
