#!/usr/bin/env python3
"""store.py — the SQLite editorial review store for the kigo-2026 fill workflow.

The editorial source of truth that sits between the deterministic generators
(spine facts, LLM prose, fetched image candidates) and the assemble.py gate.
Separates regenerable/derived data from durable human decisions (edits, the
chosen image, approval). One reconciliation rule — "approved freezes": an
approved day is never mutated by spine/generate; unapproved days are drafts.

Stdlib + Pillow (via fetch_images). See docs/adr/0025-sqlite-editorial-review-store.md.
"""
import datetime as dt
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_csv  # noqa: E402  (CONTRACT_COLUMNS)
import fetch_images as _fi  # noqa: E402  (image_id_for, image_row_from_candidate)

DAY_FACT_COLUMNS = ("kanji", "reading_ja", "reading_en", "season",
                    "subseason", "category", "gloss_en")
DAY_PROSE_COLUMNS = ("translation_en", "description_ja", "description_en")
_DAY_WRITABLE = set(DAY_FACT_COLUMNS) | set(DAY_PROSE_COLUMNS)

_SCHEMA = """
CREATE TABLE IF NOT EXISTS days (
    date TEXT PRIMARY KEY,
    kanji TEXT NOT NULL DEFAULT '',
    reading_ja TEXT NOT NULL DEFAULT '',
    reading_en TEXT NOT NULL DEFAULT '',
    season TEXT NOT NULL DEFAULT '',
    subseason TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT '',
    gloss_en TEXT NOT NULL DEFAULT '',
    translation_en TEXT NOT NULL DEFAULT '',
    description_ja TEXT NOT NULL DEFAULT '',
    description_en TEXT NOT NULL DEFAULT '',
    chosen_candidate_id INTEGER REFERENCES candidates(id) ON DELETE SET NULL,
    approved INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS candidates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL REFERENCES days(date) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT '',
    search_term TEXT NOT NULL DEFAULT '',
    search_lang TEXT NOT NULL DEFAULT '',
    photographer TEXT NOT NULL DEFAULT '',
    license_ja TEXT NOT NULL DEFAULT '',
    license_en TEXT NOT NULL DEFAULT '',
    title_ja TEXT NOT NULL DEFAULT '',
    title_en TEXT NOT NULL DEFAULT '',
    source_url TEXT NOT NULL DEFAULT '',
    src_w INTEGER NOT NULL DEFAULT 0,
    src_h INTEGER NOT NULL DEFAULT 0,
    out_file TEXT NOT NULL DEFAULT '',
    usable TEXT NOT NULL DEFAULT 'yes',
    note TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_candidates_date ON candidates(date);
"""


def _now():
    return dt.datetime.now().isoformat(timespec="seconds")


def connect(path):
    # check_same_thread=False: the review webapp's http.server handles requests
    # synchronously (one at a time, never concurrently) but its serve_forever()
    # loop runs on a thread distinct from the one that called connect() — the
    # CLI path (fill.py review) calls both from the main thread, but tests spin
    # the server up on a background thread. No concurrent access ever occurs,
    # so relaxing sqlite3's same-thread guard here is safe.
    conn = sqlite3.connect(str(path), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.executescript(_SCHEMA)
    conn.commit()
    return conn


def seed_days(conn, rows, force=False):
    seeded = skipped = 0
    for row in rows:
        date = row["date"]
        existing = conn.execute("SELECT approved FROM days WHERE date = ?", (date,)).fetchone()
        if existing and existing["approved"] and not force:
            skipped += 1
            continue
        cols = list(DAY_FACT_COLUMNS)
        vals = [row.get(c, "") for c in cols]
        if existing:
            assignments = ", ".join(f"{c} = ?" for c in cols)
            conn.execute(f"UPDATE days SET {assignments}, updated_at = ? WHERE date = ?",
                         (*vals, _now(), date))
        else:
            placeholders = ", ".join(["?"] * (len(cols) + 3))
            conn.execute(
                f"INSERT INTO days (date, {', '.join(cols)}, created_at, updated_at) "
                f"VALUES ({placeholders})",
                (date, *vals, _now(), _now()))
        seeded += 1
    conn.commit()
    return seeded, skipped


def get_day(conn, date):
    row = conn.execute("SELECT * FROM days WHERE date = ?", (date,)).fetchone()
    return dict(row) if row else None


def list_days(conn, date_from=None, date_to=None, status=None):
    clauses, params = [], []
    if date_from:
        clauses.append("date >= ?"); params.append(date_from)
    if date_to:
        clauses.append("date <= ?"); params.append(date_to)
    if status == "approved":
        clauses.append("approved = 1")
    elif status == "unapproved":
        clauses.append("approved = 0")
    where = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    rows = conn.execute(f"SELECT * FROM days{where} ORDER BY date", params).fetchall()
    return [dict(r) for r in rows]


def set_day_fields(conn, date, **fields):
    bad = set(fields) - _DAY_WRITABLE
    if bad:
        raise ValueError(f"non-writable day columns: {sorted(bad)}")
    if not fields:
        return
    assignments = ", ".join(f"{c} = ?" for c in fields)
    conn.execute(f"UPDATE days SET {assignments}, updated_at = ? WHERE date = ?",
                 (*fields.values(), _now(), date))
    conn.commit()


def set_approved(conn, date, approved):
    conn.execute("UPDATE days SET approved = ?, updated_at = ? WHERE date = ?",
                 (1 if approved else 0, _now(), date))
    conn.commit()


CANDIDATE_STORE_COLUMNS = ("provider", "search_term", "search_lang", "photographer",
                           "license_ja", "license_en", "title_ja", "title_en",
                           "source_url", "src_w", "src_h", "out_file", "usable", "note")


def add_candidate(conn, date, cand):
    cols = list(CANDIDATE_STORE_COLUMNS)
    vals = [cand.get(c, "") for c in cols]
    placeholders = ", ".join(["?"] * (len(cols) + 1))
    cur = conn.execute(
        f"INSERT INTO candidates (date, {', '.join(cols)}) VALUES ({placeholders})",
        (date, *vals))
    conn.commit()
    return cur.lastrowid


def get_candidates(conn, date):
    rows = conn.execute("SELECT * FROM candidates WHERE date = ? ORDER BY id",
                        (date,)).fetchall()
    return [dict(r) for r in rows]


def clear_candidates(conn, date):
    conn.execute("UPDATE days SET chosen_candidate_id = NULL, updated_at = ? WHERE date = ?",
                 (_now(), date))
    conn.execute("DELETE FROM candidates WHERE date = ?", (date,))
    conn.commit()


def set_chosen(conn, date, candidate_id):
    row = conn.execute("SELECT date, usable FROM candidates WHERE id = ?",
                       (candidate_id,)).fetchone()
    if row is None or row["date"] != date:
        raise ValueError(f"candidate {candidate_id} does not belong to {date}")
    if (row["usable"] or "").strip().lower() == "no":
        raise ValueError(f"candidate {candidate_id} is reference-only, not shippable")
    conn.execute("UPDATE days SET chosen_candidate_id = ?, updated_at = ? WHERE date = ?",
                 (candidate_id, _now(), date))
    conn.commit()


def _contract_row(day, cand):
    image_id = _fi.image_id_for(day["date"])
    cand_row = {"date": day["date"], "image_id": image_id,
                "title_ja": cand["title_ja"], "title_en": cand["title_en"],
                "photographer": cand["photographer"], "provider": cand["provider"],
                "license_ja": cand["license_ja"], "license_en": cand["license_en"]}
    attribution = _fi.image_row_from_candidate(cand_row)  # 8 IMAGE_COLUMNS fields
    row = {
        "date": day["date"], "kanji": day["kanji"],
        "reading_ja": day["reading_ja"], "reading_en": day["reading_en"],
        "translation_en": day["translation_en"],
        "description_ja": day["description_ja"], "description_en": day["description_en"],
        "image_id": image_id,
        "attribution_title_ja": attribution["attribution_title_ja"],
        "attribution_title_en": attribution["attribution_title_en"],
        "attribution_credit_ja": attribution["attribution_credit_ja"],
        "attribution_credit_en": attribution["attribution_credit_en"],
        "attribution_license_ja": attribution["attribution_license_ja"],
        "attribution_license_en": attribution["attribution_license_en"],
    }
    row["_out_file"] = cand["out_file"]
    return row


def export_rows(conn, date_from=None, date_to=None):
    out = []
    for day in list_days(conn, date_from, date_to, status="approved"):
        cid = day["chosen_candidate_id"]
        if cid is None:
            continue
        cand = conn.execute("SELECT * FROM candidates WHERE id = ?", (cid,)).fetchone()
        if cand is None:
            continue
        out.append(_contract_row(day, dict(cand)))
    return out


def pending_dates(conn, date_from=None, date_to=None):
    exportable = {r["date"] for r in export_rows(conn, date_from, date_to)}
    return [d["date"] for d in list_days(conn, date_from, date_to)
            if d["date"] not in exportable]
