"""assembler.py — the deterministic (rows, existing Kō/Sekki, config) -> manifest
dict step of the pipeline.

Copies the base manifest's `ko` and `sekki` lists through **unmodified** (same
objects, same nested key order) so the assembled manifest's Kō/Sekki sections
stay byte-for-byte identical to the bundled manifest's when both are
serialized the same way. Only `dailyMap` and the top-level metadata
(`version`, `imageBaseURL`) change.
"""
import json
from pathlib import Path

# Placeholder https host, matching the existing RemoteManifestSource placeholder
# convention (Sources/Kigo/RemoteManifestSource.swift) — no real CDN is stood up
# by this slice (C25/C26 own real image delivery).
DEFAULT_IMAGE_BASE_URL = "https://placeholder.kigo.example/images"


def load_base_manifest(path) -> dict:
    """Loads the existing manifest (default: the bundled Resources/manifest.json)
    that supplies the Kō/Sekki content to copy through untouched."""
    return json.loads(Path(path).read_text(encoding="utf-8"))


def assemble_manifest(rows: list[dict], base_manifest: dict, image_base_url: str = DEFAULT_IMAGE_BASE_URL) -> dict:
    """Builds the assembled manifest dict from parsed CSV `rows` (as produced by
    `csv_parser.parse_rows`) and `base_manifest` (as produced by
    `load_base_manifest`).

    - `dailyMap` is built entirely from `rows`, keyed by each row's date.
    - `ko` / `sekki` are copied through from `base_manifest` untouched.
    - `schemaVersion` is copied through; `version` is bumped past the base
      manifest's version (deterministic given a fixed base manifest, so two
      assembles of the same CSV over the same base manifest agree).
    - `imageBaseURL` is set to `image_base_url` (an additive, optional field —
      ADR 0014 forward-compat; existing decoding of manifests without it is
      unaffected).
    """
    daily_map = {row["date"]: row["entry"] for row in rows}
    return {
        "schemaVersion": base_manifest["schemaVersion"],
        "version": base_manifest["version"] + 1,
        "dailyMap": daily_map,
        "ko": base_manifest["ko"],
        "sekki": base_manifest["sekki"],
        "imageBaseURL": image_base_url,
    }


def write_manifest(manifest: dict, out_path) -> None:
    """Writes `manifest` to `out_path` with stable, deterministic formatting
    (fixed key order as constructed, indent=2, literal non-ASCII text) so that
    assembling the same input twice produces byte-identical files."""
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
