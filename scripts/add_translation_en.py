#!/usr/bin/env python3
"""add_translation_en.py — one-shot, idempotent augmenter that adds a
`translationEn` field to every Daily Map entry in Resources/manifest.json.

The bundled manifest is instrumented DUMMY content (ADR 0016) that real content
(built via scripts/content/fill/ + assemble.py, which already emit translationEn)
will eventually replace. Until then, the app and its tests still need the new
free-Encounter field (ADR 0024) present on every entry, so this derives a clean
English name from the leading clause of each entry's existing English
description (stripping the `(YYYY-MM-DD)` instrumentation stamp first).

Deterministic and idempotent: re-running recomputes the same value. Mirrors the
existing add_ko_en.py / add_sekki_en.py / localize_manifest.py augmenters.

Usage (run from repo root):
    python3 scripts/add_translation_en.py
"""
import json
import os
import re

# Separators that end the "name" clause of a dummy English description. A bare
# word hyphen ("Cherry-blossom") is deliberately NOT a separator — only an
# em/en dash flanked by spaces, or a comma/semicolon/colon/sentence stop.
_CLAUSE_END = re.compile(r"\s[—–]\s|;|:|,\s|\.\s|\.$")
_DATE_STAMP = re.compile(r"\s*\(\d{4}-\d{2}-\d{2}\)\s*$")


def translation_from_description(description_en: str) -> str:
    text = _DATE_STAMP.sub("", (description_en or "").strip())
    lead = _CLAUSE_END.split(text, maxsplit=1)[0].strip()
    return lead or text


def main() -> None:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    manifest_path = os.path.join(repo_root, "Resources", "manifest.json")

    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)

    daily_map = manifest.get("dailyMap", {})
    for key, entry in daily_map.items():
        description_en = (entry.get("description") or {}).get("en") or ""
        translation = translation_from_description(description_en)
        assert translation, f"Entry '{key}' produced an empty translationEn"
        entry["translationEn"] = translation

    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Added translationEn to {len(daily_map)} daily map entries in {manifest_path}")


if __name__ == "__main__":
    main()
