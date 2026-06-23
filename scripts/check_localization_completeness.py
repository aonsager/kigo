#!/usr/bin/env python3
"""
check_localization_completeness.py — Validates that every Daily Map entry, every
Kō entry, and every Sekki entry in Resources/manifest.json has non-empty English
localization fields.

Usage:
    python3 scripts/check_localization_completeness.py [path/to/manifest.json]

Exits 0 if all sections pass, 1 if any fail.
"""

import json
import sys
import os


def check_daily_map(manifest: dict) -> bool:
    failures: list[str] = []
    for key, entry in manifest.get("dailyMap", {}).items():
        reading_en = entry.get("reading", {}).get("en", "")
        desc_en = entry.get("description", {}).get("en", "")
        title_en = entry.get("attribution", {}).get("title", {}).get("en", "")
        credit_en = entry.get("attribution", {}).get("credit", {}).get("en", "")
        license_en = entry.get("attribution", {}).get("license", {}).get("en", "")

        missing = []
        if not reading_en:
            missing.append("reading.en")
        if not desc_en:
            missing.append("description.en")
        if not title_en:
            missing.append("attribution.title.en")
        if not credit_en:
            missing.append("attribution.credit.en")
        if not license_en:
            missing.append("attribution.license.en")

        if missing:
            failures.append(f"  {key}: missing {', '.join(missing)}")

    if failures:
        print(f"FAIL daily-map: {len(failures)} entries missing EN fields:")
        for f in failures:
            print(f)
        return False
    else:
        print("OK: all daily map EN fields present")
        return True


def check_ko(manifest: dict) -> bool:
    failures: list[str] = []
    for entry in manifest.get("ko", []):
        kanji = entry.get("kanji", "<unknown>")
        reading_en = entry.get("reading", {}).get("en", "")
        desc_en = entry.get("description", {}).get("en", "")

        missing = []
        if not reading_en:
            missing.append("reading.en")
        if not desc_en:
            missing.append("description.en")

        if missing:
            failures.append(f"  {kanji}: missing {', '.join(missing)}")

    if failures:
        print(f"FAIL ko: {len(failures)} entries missing EN fields:")
        for f in failures:
            print(f)
        return False
    else:
        ko_count = len(manifest.get("ko", []))
        print(f"OK: all {ko_count} kō EN fields present")
        return True


def check_sekki(manifest: dict) -> bool:
    failures: list[str] = []
    for entry in manifest.get("sekki", []):
        kanji = entry.get("kanji", "<unknown>")
        reading_en = entry.get("reading", {}).get("en", "")
        gloss_en = entry.get("gloss", {}).get("en", "")
        desc_en = entry.get("description", {}).get("en", "")

        missing = []
        if not reading_en:
            missing.append("reading.en")
        if not gloss_en:
            missing.append("gloss.en")
        if not desc_en:
            missing.append("description.en")

        if missing:
            failures.append(f"  {kanji}: missing {', '.join(missing)}")

    if failures:
        print(f"FAIL sekki: {len(failures)} entries missing EN fields:")
        for f in failures:
            print(f)
        return False
    else:
        sekki_count = len(manifest.get("sekki", []))
        print(f"OK: all {sekki_count} sekki EN fields present")
        return True


def check(manifest_path: str) -> bool:
    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)

    daily_ok = check_daily_map(manifest)
    ko_ok = check_ko(manifest)
    sekki_ok = check_sekki(manifest)

    return daily_ok and ko_ok and sekki_ok


def main() -> None:
    if len(sys.argv) > 1:
        manifest_path = sys.argv[1]
    else:
        repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        manifest_path = os.path.join(repo_root, "Resources", "manifest.json")

    if not check(manifest_path):
        sys.exit(1)


if __name__ == "__main__":
    main()
