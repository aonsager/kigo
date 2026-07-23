#!/usr/bin/env python3
"""store.py — the SQLite editorial review store for the kigo-2026 fill workflow.

The editorial source of truth that sits between the deterministic generators
(spine facts, LLM prose) and the assemble.py gate. Separates regenerable/derived
data from durable human decisions (edits, approval). One reconciliation rule —
"approved freezes": an approved day is never mutated by spine/generate;
unapproved days are drafts.

Stdlib only. See docs/adr/0025-sqlite-editorial-review-store.md.
"""
import datetime as dt
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_csv  # noqa: E402  (CONTRACT_COLUMNS)

DAY_FACT_COLUMNS = ("kanji", "reading_ja", "reading_en", "season",
                    "subseason", "category", "gloss_en")
DAY_PROSE_COLUMNS = ("translation_en", "description_ja", "description_en")
_DAY_WRITABLE = set(DAY_FACT_COLUMNS) | set(DAY_PROSE_COLUMNS)

# Bumped when the on-disk schema changes; connect() migrates older DBs forward.
# v1: image pivot (ADR 0026) — dropped the candidates table + chosen_candidate_id.
_SCHEMA_VERSION = 1

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
    approved INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT ''
);
"""


def _now():
    return dt.datetime.now().isoformat(timespec="seconds")


def _migrate(conn):
    """Forward-migrate an older on-disk schema, preserving every `days` row.
    Idempotent and guarded by PRAGMA user_version."""
    version = conn.execute("PRAGMA user_version").fetchone()[0]
    if version >= _SCHEMA_VERSION:
        return
    # v0 -> v1 (ADR 0026): drop the chosen_candidate_id column and candidates
    # table. Column drop first so the FK reference is gone before the table.
    cols = {r[1] for r in conn.execute("PRAGMA table_info(days)")}
    if "chosen_candidate_id" in cols:
        if sqlite3.sqlite_version_info >= (3, 35, 0):
            conn.execute("ALTER TABLE days DROP COLUMN chosen_candidate_id")
        else:
            _rebuild_days_dropping_chosen(conn)
    conn.execute("DROP TABLE IF EXISTS candidates")
    conn.execute(f"PRAGMA user_version = {_SCHEMA_VERSION}")
    conn.commit()


def _rebuild_days_dropping_chosen(conn):
    """Fallback for SQLite < 3.35 (no ALTER TABLE DROP COLUMN): rebuild `days`
    copying every retained column."""
    keep = ("date", *DAY_FACT_COLUMNS, *DAY_PROSE_COLUMNS,
            "approved", "created_at", "updated_at")
    collist = ", ".join(keep)
    conn.executescript(_SCHEMA.replace("days", "days_new"))
    conn.execute(f"INSERT INTO days_new ({collist}) SELECT {collist} FROM days")
    conn.execute("DROP TABLE days")
    conn.execute("ALTER TABLE days_new RENAME TO days")


def connect(path):
    # check_same_thread=False: the review webapp serves requests synchronously
    # (never concurrently) but serve_forever() runs on a thread distinct from the
    # one that called connect(); tests spin the server on a background thread. No
    # concurrent access occurs, so relaxing the same-thread guard is safe.
    conn = sqlite3.connect(str(path), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.executescript(_SCHEMA)
    conn.commit()
    _migrate(conn)
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


# The fields the contract/validator require non-empty for a shippable row
# (mirrors scripts/content/validator.py — a day that passes here passes assemble).
_REQUIRED_FOR_EXPORT = ("kanji", "reading_ja", "reading_en", "translation_en",
                        "description_ja", "description_en")


def _is_complete(day):
    return all((day.get(c) or "").strip() for c in _REQUIRED_FOR_EXPORT)


def export_rows(conn, date_from=None, date_to=None):
    """Approved, prose-complete days as 7-column contract rows (keyed exactly by
    build_csv.CONTRACT_COLUMNS). Images are no longer part of the gate (ADR 0026)."""
    out = []
    for day in list_days(conn, date_from, date_to, status="approved"):
        if not _is_complete(day):
            continue
        out.append({c: day[c] for c in build_csv.CONTRACT_COLUMNS})
    return out


def pending_dates(conn, date_from=None, date_to=None):
    exportable = {r["date"] for r in export_rows(conn, date_from, date_to)}
    return [d["date"] for d in list_days(conn, date_from, date_to)
            if d["date"] not in exportable]
