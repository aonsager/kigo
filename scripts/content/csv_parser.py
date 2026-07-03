"""csv_parser.py — reads the reviewable source CSV and produces validated row
records, owning the column contract between the human-editable CSV and the
manifest's DailyMapEntry shape.

Column contract (one row per date):
    date, kanji, reading_ja, reading_en, description_ja, description_en,
    image_id, attribution_title_ja, attribution_title_en,
    attribution_credit_ja, attribution_credit_en, attribution_license_ja,
    attribution_license_en

Every column is required and non-empty for every row. This is deliberately
light validation ("don't write a structurally broken manifest") — the full
malformed-row-rejection *gate* (clear per-error-code diagnostics, docs) is
slice 2 (#200); here a bad row simply raises `CSVParseError` and the CLI never
reaches the write step.
"""
import csv
import re
from pathlib import Path

REQUIRED_COLUMNS = (
    "date",
    "kanji",
    "reading_ja",
    "reading_en",
    "description_ja",
    "description_en",
    "image_id",
    "attribution_title_ja",
    "attribution_title_en",
    "attribution_credit_ja",
    "attribution_credit_en",
    "attribution_license_ja",
    "attribution_license_en",
)

_DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")


class CSVParseError(ValueError):
    """Raised when the source CSV is missing columns, empty, or a row is
    missing a required value. Deliberately minimal — see module docstring."""


def parse_rows(csv_path) -> list[dict]:
    """Parses `csv_path` into a list of row records, each shaped:

        {"date": "2026-03-21", "entry": {<DailyMapEntry-shaped dict>}}

    Raises `CSVParseError` on a missing/empty required column, an empty CSV,
    or a malformed date, before any row is returned.
    """
    csv_path = Path(csv_path)
    with csv_path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            raise CSVParseError(f"{csv_path}: empty CSV, no header row")
        missing_columns = [c for c in REQUIRED_COLUMNS if c not in reader.fieldnames]
        if missing_columns:
            raise CSVParseError(
                f"{csv_path}: missing required column(s): {', '.join(missing_columns)}"
            )
        rows = [
            _row_to_record(raw, csv_path=csv_path, line_no=line_no)
            for line_no, raw in enumerate(reader, start=2)  # header is line 1
        ]

    if not rows:
        raise CSVParseError(f"{csv_path}: no data rows")
    return rows


def _row_to_record(raw: dict, *, csv_path: Path, line_no: int) -> dict:
    values = {}
    for column in REQUIRED_COLUMNS:
        value = (raw.get(column) or "").strip()
        if not value:
            raise CSVParseError(f"{csv_path}:{line_no}: column '{column}' is required and must be non-empty")
        values[column] = value

    if not _DATE_RE.fullmatch(values["date"]):
        raise CSVParseError(f"{csv_path}:{line_no}: date '{values['date']}' must be YYYY-MM-DD")

    return {
        "date": values["date"],
        "entry": {
            "kanji": values["kanji"],
            "reading": {"ja": values["reading_ja"], "en": values["reading_en"]},
            "description": {"ja": values["description_ja"], "en": values["description_en"]},
            "imageId": values["image_id"],
            "attribution": {
                "title": {"ja": values["attribution_title_ja"], "en": values["attribution_title_en"]},
                "credit": {"ja": values["attribution_credit_ja"], "en": values["attribution_credit_en"]},
                "license": {"ja": values["attribution_license_ja"], "en": values["attribution_license_en"]},
            },
        },
    }
