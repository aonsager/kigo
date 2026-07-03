"""Deterministic, offline checks for the CSV-to-manifest content-assembly
pipeline (C24 slice 1: #199). No network, no third-party deps (stdlib only) —
matches the repo's existing scripts/test_arbiter_fixtures.py convention.

Run directly:
    python3 scripts/content/test_pipeline.py
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ASSEMBLE_PY = REPO_ROOT / "scripts" / "content" / "assemble.py"
WORKED_EXAMPLE_CSV = REPO_ROOT / "content" / "kigo-2026.example.csv"
BUNDLED_MANIFEST = REPO_ROOT / "Resources" / "manifest.json"

# Running this file directly (python3 scripts/content/test_pipeline.py) already
# puts its own directory on sys.path[0]; this insert makes that explicit and
# keeps the bare `import url_deriver` etc. below working if this file is ever
# invoked from a different cwd.
sys.path.insert(0, str(Path(__file__).resolve().parent))

import assembler  # noqa: E402
import csv_parser  # noqa: E402
import url_deriver  # noqa: E402

_FAKE_BASE_MANIFEST = {
    "schemaVersion": "2.0",
    "version": 1,
    "dailyMap": {"2026-01-01": {"kanji": "dummy", "reading": {"ja": "x"}, "description": {"ja": "y"},
                                 "imageId": "z", "attribution": {"title": {"ja": "a"}, "credit": {"ja": "b"},
                                                                  "license": {"ja": "c"}}}},
    "ko": [{"kanji": "東風解凍", "reading": {"ja": "はるかぜこおりをとく", "en": "harukazekōriotoku"},
            "gloss": "east wind thaws the ice", "sekkiId": "risshun",
            "dateRange": {"start": "02-04", "end": "02-08"},
            "description": {"ja": "春の東風が川や湖の氷を解かし始める。", "en": "The spring east wind begins to thaw."}}],
    "sekki": [{"id": "risshun", "kanji": "立春", "reading": {"ja": "りっしゅん", "en": "risshun"},
               "gloss": {"ja": "春の始まり", "en": "Start of Spring"},
               "description": {"ja": "太陽が黄経315度に達する日。", "en": "The first solar term of the year."}}],
}

_SAMPLE_CSV_HEADER = (
    "date,kanji,reading_ja,reading_en,description_ja,description_en,image_id,"
    "attribution_title_ja,attribution_title_en,attribution_credit_ja,attribution_credit_en,"
    "attribution_license_ja,attribution_license_en\n"
)
_SAMPLE_CSV_ROW = (
    "2026-03-21,桜,さくら,sakura,"
    "\"川沿いの土手が薄紅色に染まり、人々が下を歩いて花を見上げる。\","
    "\"Pink washes over the riverbank path; people slow their walk to look up.\","
    "kigo-03-21,桜,Cherry Blossom,撮影者不明,Unknown photographer,"
    "パブリックドメイン,Public domain\n"
)


def _write_sample_csv(tmp_dir: str, *, rows: str = _SAMPLE_CSV_ROW) -> Path:
    path = Path(tmp_dir) / "sample.csv"
    path.write_text(_SAMPLE_CSV_HEADER + rows, encoding="utf-8")
    return path


def test_url_deriver_builds_convention_url():
    url = url_deriver.derive_image_url("https://cdn.example/img", "kigo-06-12")
    assert url == "https://cdn.example/img/kigo-06-12.jpg", url


def test_csv_parser_maps_row_to_entry_shape():
    with tempfile.TemporaryDirectory() as tmp:
        rows = csv_parser.parse_rows(_write_sample_csv(tmp))

    assert len(rows) == 1
    row = rows[0]
    assert row["date"] == "2026-03-21"
    entry = row["entry"]
    assert entry["kanji"] == "桜"
    assert entry["reading"] == {"ja": "さくら", "en": "sakura"}
    assert entry["description"]["ja"].startswith("川沿い")
    assert entry["description"]["en"].startswith("Pink washes")
    assert entry["imageId"] == "kigo-03-21"
    assert entry["attribution"]["title"] == {"ja": "桜", "en": "Cherry Blossom"}
    assert entry["attribution"]["credit"] == {"ja": "撮影者不明", "en": "Unknown photographer"}
    assert entry["attribution"]["license"] == {"ja": "パブリックドメイン", "en": "Public domain"}


def test_csv_parser_rejects_row_with_empty_required_field():
    # Minimal, incidental malformed-input handling ("falls out naturally") —
    # the full validator gate with per-error-code diagnostics is slice 2 (#200).
    blank_reading_row = (
        "2026-03-21,桜,,sakura,"
        "\"川沿いの土手が薄紅色に染まり、人々が下を歩いて花を見上げる。\","
        "\"Pink washes over the riverbank path; people slow their walk to look up.\","
        "kigo-03-21,桜,Cherry Blossom,撮影者不明,Unknown photographer,"
        "パブリックドメイン,Public domain\n"
    )
    with tempfile.TemporaryDirectory() as tmp:
        csv_path = _write_sample_csv(tmp, rows=blank_reading_row)
        try:
            csv_parser.parse_rows(csv_path)
            raise AssertionError("expected CSVParseError for a blank required field")
        except csv_parser.CSVParseError as e:
            assert "reading_ja" in str(e)


def test_assembler_sets_metadata_and_passes_ko_sekki_through_untouched():
    with tempfile.TemporaryDirectory() as tmp:
        rows = csv_parser.parse_rows(_write_sample_csv(tmp))

    manifest = assembler.assemble_manifest(rows, _FAKE_BASE_MANIFEST, image_base_url="https://cdn.example/img")

    assert manifest["schemaVersion"] == "2.0"
    assert manifest["version"] == 2, "version must bump past the base manifest's version"
    assert manifest["imageBaseURL"] == "https://cdn.example/img"
    assert manifest["dailyMap"] == {rows[0]["date"]: rows[0]["entry"]}

    # Ko/Sekki copied through untouched: byte-identical when serialized the
    # same way (same objects, same nested key order — no reordering/rebuilding).
    assert json.dumps(manifest["ko"], ensure_ascii=False) == json.dumps(_FAKE_BASE_MANIFEST["ko"], ensure_ascii=False)
    assert json.dumps(manifest["sekki"], ensure_ascii=False) == json.dumps(_FAKE_BASE_MANIFEST["sekki"], ensure_ascii=False)


def test_write_manifest_is_idempotent_byte_identical():
    with tempfile.TemporaryDirectory() as tmp:
        rows = csv_parser.parse_rows(_write_sample_csv(tmp))
        out1, out2 = Path(tmp) / "m1.json", Path(tmp) / "m2.json"
        assembler.write_manifest(assembler.assemble_manifest(rows, _FAKE_BASE_MANIFEST), out1)
        assembler.write_manifest(assembler.assemble_manifest(rows, _FAKE_BASE_MANIFEST), out2)
        assert out1.read_bytes() == out2.read_bytes()


def _run_assemble_cli(*, csv_path: Path, out_path: Path, manifest_path: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(ASSEMBLE_PY),
         "--csv", str(csv_path), "--out", str(out_path), "--manifest", str(manifest_path)],
        capture_output=True, text=True,
    )


def test_cli_assembles_csv_and_manifest_into_out_file():
    with tempfile.TemporaryDirectory() as tmp:
        csv_path = _write_sample_csv(tmp)
        manifest_path = Path(tmp) / "base-manifest.json"
        manifest_path.write_text(json.dumps(_FAKE_BASE_MANIFEST), encoding="utf-8")
        out_path = Path(tmp) / "assembled.json"

        result = _run_assemble_cli(csv_path=csv_path, out_path=out_path, manifest_path=manifest_path)

        assert result.returncode == 0, result.stderr
        manifest = json.loads(out_path.read_text(encoding="utf-8"))
        assert manifest["version"] == 2
        assert manifest["dailyMap"] == {"2026-03-21": {
            "kanji": "桜",
            "reading": {"ja": "さくら", "en": "sakura"},
            "description": {
                "ja": "川沿いの土手が薄紅色に染まり、人々が下を歩いて花を見上げる。",
                "en": "Pink washes over the riverbank path; people slow their walk to look up.",
            },
            "imageId": "kigo-03-21",
            "attribution": {
                "title": {"ja": "桜", "en": "Cherry Blossom"},
                "credit": {"ja": "撮影者不明", "en": "Unknown photographer"},
                "license": {"ja": "パブリックドメイン", "en": "Public domain"},
            },
        }}


def test_cli_writes_nothing_and_exits_nonzero_on_malformed_csv():
    with tempfile.TemporaryDirectory() as tmp:
        blank_reading_row = (
            "2026-03-21,桜,,sakura,d,d,kigo-03-21,桜,Cherry Blossom,撮影者不明,Unknown photographer,"
            "パブリックドメイン,Public domain\n"
        )
        csv_path = _write_sample_csv(tmp, rows=blank_reading_row)
        manifest_path = Path(tmp) / "base-manifest.json"
        manifest_path.write_text(json.dumps(_FAKE_BASE_MANIFEST), encoding="utf-8")
        out_path = Path(tmp) / "assembled.json"

        result = _run_assemble_cli(csv_path=csv_path, out_path=out_path, manifest_path=manifest_path)

        assert result.returncode != 0
        assert not out_path.exists(), "a malformed CSV must never produce an output file"


def test_worked_example_assembles_into_a_valid_localized_manifest():
    # The acceptance-level round trip (mirrors docs/GOAL.md's C24 evidence):
    # assemble the real worked-example CSV against the real bundled manifest.
    base = assembler.load_base_manifest(BUNDLED_MANIFEST)
    rows = csv_parser.parse_rows(WORKED_EXAMPLE_CSV)
    assert len(rows) >= 8, "worked example needs >=8 rows"

    manifest = assembler.assemble_manifest(rows, base)

    assert manifest["schemaVersion"] == base["schemaVersion"]
    assert manifest["version"] == base["version"] + 1
    assert manifest["imageBaseURL"].startswith("https://")
    assert len(manifest["ko"]) == 72 and len(manifest["sekki"]) == 24
    assert json.dumps(manifest["ko"], ensure_ascii=False) == json.dumps(base["ko"], ensure_ascii=False)
    assert json.dumps(manifest["sekki"], ensure_ascii=False) == json.dumps(base["sekki"], ensure_ascii=False)

    assert len(manifest["dailyMap"]) == len(rows)
    for date_key, entry in manifest["dailyMap"].items():
        assert re.fullmatch(r"2026-\d{2}-\d{2}", date_key), date_key
        assert entry["kanji"] and entry["imageId"]
        blob = entry["description"]["ja"] + entry["description"]["en"]
        assert not re.search(r"\(20\d\d-\d\d-\d\d\)", blob), f"{date_key}: leftover dummy date-stamp"
        for field in ("reading", "description"):
            assert entry[field]["ja"] and entry[field]["en"], f"{date_key}.{field} needs ja+en"
        for sub in ("title", "credit", "license"):
            attr = entry["attribution"][sub]
            assert attr["ja"] and attr["en"], f"{date_key}.attribution.{sub} needs ja+en"


def test_cli_end_to_end_over_worked_example_is_idempotent_and_leaves_bundled_manifest_untouched():
    bundled_before = BUNDLED_MANIFEST.read_bytes()
    with tempfile.TemporaryDirectory() as tmp:
        out1, out2 = Path(tmp) / "wm1.json", Path(tmp) / "wm2.json"

        result1 = _run_assemble_cli(csv_path=WORKED_EXAMPLE_CSV, out_path=out1, manifest_path=BUNDLED_MANIFEST)
        assert result1.returncode == 0, result1.stderr
        result2 = _run_assemble_cli(csv_path=WORKED_EXAMPLE_CSV, out_path=out2, manifest_path=BUNDLED_MANIFEST)
        assert result2.returncode == 0, result2.stderr

        assert out1.read_bytes() == out2.read_bytes(), "assembling the same CSV twice must be byte-identical"

    assert BUNDLED_MANIFEST.read_bytes() == bundled_before, "the bundled manifest must never be modified"


if __name__ == "__main__":
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print("ALL PASS")
