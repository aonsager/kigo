#!/usr/bin/env python3
"""assemble.py — CSV-to-manifest content-assembly pipeline (C24 slice 1: #199,
validator gate: slice 2 #200).

Reads a reviewable source CSV of Daily Map entries together with the existing
bundled Kō/Sekki content and writes a complete, deterministic, localized
manifest to the given --out path. Never touches the source CSV or the
default --manifest input; only ever writes to --out — and only once every
row has passed both gates: `csv_parser` (structural completeness) and
`validator` (bilingual completeness, no leftover date-stamp instrumentation,
a well-formed derived image URL). A failure at either gate exits nonzero and
writes nothing, leaving anything already at --out untouched. See
content/README.md for the full CSV column contract and workflow.

Usage (run from the repo root):
    python3 scripts/content/assemble.py --csv content/kigo-2026.example.csv --out /tmp/manifest.json

Running the same CSV through twice (same --manifest input) produces
byte-identical output — see scripts/content/test_pipeline.py.
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import assembler  # noqa: E402
import csv_parser  # noqa: E402
import validator  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BASE_MANIFEST = REPO_ROOT / "Resources" / "manifest.json"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Assemble a Daily Map manifest from a source CSV.")
    parser.add_argument("--csv", required=True, type=Path, help="Path to the reviewed source CSV")
    parser.add_argument("--out", required=True, type=Path, help="Path to write the assembled manifest JSON")
    parser.add_argument(
        "--manifest", type=Path, default=DEFAULT_BASE_MANIFEST,
        help="Path to the existing manifest to source Kō/Sekki + schemaVersion/version from "
             "(default: the bundled Resources/manifest.json)",
    )
    parser.add_argument(
        "--image-base-url", default=assembler.DEFAULT_IMAGE_BASE_URL, dest="image_base_url",
        help="Top-level imageBaseURL to stamp into the assembled manifest",
    )
    args = parser.parse_args(argv)

    try:
        rows = csv_parser.parse_rows(args.csv)
        base_manifest = assembler.load_base_manifest(args.manifest)
        manifest = assembler.assemble_manifest(rows, base_manifest, image_base_url=args.image_base_url)
        validator.validate_manifest(manifest)
    except (csv_parser.CSVParseError, validator.ValidationError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    # Only reached once the manifest is fully built in memory *and* has
    # passed the validator gate, so a parse, assembly, or validation failure
    # above never leaves a partial/broken file at --out, and never touches
    # whatever (if anything) already exists there.
    assembler.write_manifest(manifest, args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
