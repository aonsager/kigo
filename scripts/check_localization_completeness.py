#\!/usr/bin/env python3
"""
check_localization_completeness.py — Validates that every Daily Map entry in
Resources/manifest.json has non-empty English localization fields.

Usage:
    python3 scripts/check_localization_completeness.py [path/to/manifest.json]

Exits 0 if all pass, 1 if any fail.
"""

import json
import sys
import os


def check(manifest_path: str) -> bool:
    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)

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
        print(f"FAIL: {len(failures)} entries missing EN fields:")
        for f in failures:
            print(f)
        return False
    else:
        print("OK: all daily map EN fields present")
        return True


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
