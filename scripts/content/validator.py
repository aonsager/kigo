"""validator.py — the pre-write gate (C24 slice 2: #200).

`csv_parser.parse_rows` already refuses a structurally incomplete row (a
required CSV column left blank) before it ever reaches assembly. This module
is the second, independent gate that runs on the *assembled* manifest, right
before `assemble.py` writes it to disk, and catches what column-presence
alone cannot:

- a leftover `(YYYY-MM-DD)` date-stamp instrumentation string in a
  description (ADR 0022 retires the old dummy-data stamp; a stamp surviving
  into real content means a row was drafted from the old template and never
  cleaned up) — the CSV parser has no way to know this pattern is invalid;
- a derived image URL that is not well-formed (most likely from a mistyped
  `--image-base-url`, since a CSV row's own `image_id` is checked for
  non-emptiness but not further shaped) — a bad base URL would otherwise
  only surface much later, at image-load time in the app.

It also re-asserts full bilingual completeness and non-empty kanji/imageId
directly against the assembled entry shape, so the gate holds even if a
future row source (not `csv_parser`) is looser about required fields.

Raises `ValidationError` — with every failing row's messages joined, one per
line — if any `dailyMap` entry fails; returns silently otherwise. Called by
`assemble.py` after `assembler.assemble_manifest` and before
`assembler.write_manifest`, so a rejected manifest is never written.
"""
import re
from urllib.parse import urlparse

import url_deriver

# Matches the dummy-data instrumentation stamp retired by ADR 0022, e.g.
# "...a quiet spring morning. (2026-03-21)".
DATE_STAMP_RE = re.compile(r"\(\d{4}-\d{2}-\d{2}\)")

_BILINGUAL_ENTRY_FIELDS = ("reading", "description")
_ATTRIBUTION_SUBFIELDS = ("title", "credit", "license")


class ValidationError(ValueError):
    """Raised with every failing row's error(s), one per line, when one or
    more assembled Daily Map entries fail the validator gate."""


def validate_entry(date: str, entry: dict, image_base_url: str) -> list[str]:
    """Returns a list of human-readable error strings for `entry` (the
    DailyMapEntry-shaped dict for `date`, as produced by `csv_parser`/
    `assembler`); empty if `entry` passes every check."""
    errors: list[str] = []

    def require(value, label: str) -> None:
        if not (value or "").strip():
            errors.append(f"{date}: {label} is required and must be non-empty")

    require(entry.get("kanji"), "kanji")
    require(entry.get("imageId"), "imageId")
    # translationEn is an English-only string (not a LocalizedText) — the free
    # Encounter's English name for the Kigo (ADR 0024). Required and non-empty.
    require(entry.get("translationEn"), "translationEn")

    for field in _BILINGUAL_ENTRY_FIELDS:
        localized = entry.get(field) or {}
        require(localized.get("ja"), f"{field}.ja")
        require(localized.get("en"), f"{field}.en")

    attribution = entry.get("attribution") or {}
    for sub in _ATTRIBUTION_SUBFIELDS:
        localized = attribution.get(sub) or {}
        require(localized.get("ja"), f"attribution.{sub}.ja")
        require(localized.get("en"), f"attribution.{sub}.en")

    description = entry.get("description") or {}
    description_blob = (description.get("ja") or "") + (description.get("en") or "")
    if DATE_STAMP_RE.search(description_blob):
        errors.append(f"{date}: description contains leftover date-stamp instrumentation, e.g. '(2026-01-01)'")

    image_id = entry.get("imageId")
    if image_id:
        url = url_deriver.derive_image_url(image_base_url, image_id)
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https") or not parsed.netloc:
            errors.append(f"{date}: derived image URL '{url}' is not well-formed (check --image-base-url)")

    return errors


def validate_manifest(manifest: dict) -> None:
    """Validates every `dailyMap` entry in `manifest` against
    `validate_entry`. Raises `ValidationError` (all rows' errors joined, one
    per line, sorted by date for a deterministic message) if any entry
    fails; returns `None` if the whole manifest passes."""
    image_base_url = manifest.get("imageBaseURL") or ""
    all_errors: list[str] = []
    for date, entry in sorted((manifest.get("dailyMap") or {}).items()):
        all_errors.extend(validate_entry(date, entry, image_base_url))

    if all_errors:
        raise ValidationError("\n".join(all_errors))
