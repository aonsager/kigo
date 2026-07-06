"""Deterministic, offline checks for the two-phase image selector
(scripts/content/fill/fetch_images.py). No network, no simulator; Pillow is used
to synthesize test images in-memory. Matches scripts/content/test_pipeline.py.

Run directly:
    python3 scripts/content/fill/test_fetch_images.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_images as fi  # noqa: E402
from PIL import Image  # noqa: E402

import subprocess, tempfile, csv as _csv  # noqa: E401

FILL_DIR = Path(__file__).resolve().parent
SCRIPT = FILL_DIR / "fetch_images.py"
README = FILL_DIR / "README.md"


def test_parse_aspect_handles_decimal():
    assert fi.parse_aspect("9:19.5") == (9.0, 19.5)
    assert fi.parse_aspect("2:3") == (2.0, 3.0)


def test_parse_aspect_rejects_malformed():
    for bad in ("", "9", "9:", "9:0", "a:b", "9:19:5"):
        try:
            fi.parse_aspect(bad)
        except ValueError:
            continue
        raise AssertionError(f"expected ValueError for {bad!r}")


def test_effective_dims_pexels_is_identity():
    assert fi.effective_dims("pexels", 4000, 6000) == (4000, 6000)


def test_effective_dims_pixabay_caps_long_edge_at_1280():
    # 4000x6000 portrait -> long edge (6000) scaled to 1280 -> ~853x1280
    w, h = fi.effective_dims("pixabay", 4000, 6000)
    assert h == 1280
    assert w == 853


def test_effective_dims_pixabay_no_upscale_when_small():
    assert fi.effective_dims("pixabay", 800, 1000) == (800, 1000)


def test_passes_floor():
    assert fi.passes_floor(1080, 2340, 800, 1200) is True
    assert fi.passes_floor(700, 2340, 800, 1200) is False
    assert fi.passes_floor(1080, 1100, 800, 1200) is False


def _row(kanji="桜", gloss_en="cherry blossom", reading_en="sakura"):
    return {"date": "2026-03-25", "kanji": kanji,
            "gloss_en": gloss_en, "reading_en": reading_en}


def test_ladder_default_order():
    rungs = fi.build_ladder(_row())
    assert rungs == [
        {"provider": "pexels", "term": "桜", "lang": "ja-JP"},
        {"provider": "pexels", "term": "cherry blossom", "lang": "en"},
        {"provider": "pixabay", "term": "桜", "lang": "ja"},
        {"provider": "pixabay", "term": "cherry blossom", "lang": "en"},
        {"provider": "pexels", "term": "sakura", "lang": "en"},
    ]


def test_ladder_no_japanese_drops_kanji_rungs():
    rungs = fi.build_ladder(_row(), use_japanese=False)
    assert all(r["lang"] == "en" for r in rungs)
    assert all(r["term"] != "桜" for r in rungs)
    assert {r["provider"] for r in rungs} == {"pexels", "pixabay"}


def test_ladder_no_fallback_drops_fallback_rungs():
    rungs = fi.build_ladder(_row(), fallback=None)
    assert all(r["provider"] == "pexels" for r in rungs)


def test_ladder_falls_back_to_romaji_when_gloss_empty():
    rungs = fi.build_ladder(_row(gloss_en=""))
    # rung 2 / 4 use reading_en ("sakura") in place of the empty gloss
    en_terms = [r["term"] for r in rungs if r["lang"] == "en"]
    assert en_terms == ["sakura", "sakura", "sakura"]


_PEXELS_SAMPLE = {
    "photos": [
        {"id": 101, "width": 4000, "height": 6000, "url": "https://pexels/p/101",
         "photographer": "Aki",
         "src": {"original": "https://img/101.jpg", "large2x": "https://img/101_2x.jpg"}},
        {"id": 102, "width": 3000, "height": 4500, "url": "https://pexels/p/102",
         "photographer": "Bo",
         "src": {"large": "https://img/102_l.jpg"}},
    ]
}

_PIXABAY_SAMPLE = {
    "hits": [
        {"id": 55, "imageWidth": 4000, "imageHeight": 6000, "pageURL": "https://pix/55",
         "user": "Cho", "largeImageURL": "https://img/55_1280.jpg",
         "webformatURL": "https://img/55_web.jpg"},
    ]
}


def test_parse_pexels_prefers_original_then_large2x():
    cands = fi._parse_pexels(_PEXELS_SAMPLE)
    assert cands[0] == {"photo_id": "101", "photographer": "Aki",
                        "download_url": "https://img/101.jpg",
                        "source_url": "https://pexels/p/101",
                        "width": 4000, "height": 6000}
    # second hit has no original -> falls through to 'large'
    assert cands[1]["download_url"] == "https://img/102_l.jpg"


def test_parse_pixabay_uses_largeimageurl():
    cands = fi._parse_pixabay(_PIXABAY_SAMPLE)
    assert cands[0] == {"photo_id": "55", "photographer": "Cho",
                        "download_url": "https://img/55_1280.jpg",
                        "source_url": "https://pix/55",
                        "width": 4000, "height": 6000}


def test_parsers_return_empty_on_no_hits():
    assert fi._parse_pexels({"photos": []}) == []
    assert fi._parse_pixabay({}) == []


def _cand(pid, w, h):
    return {"photo_id": str(pid), "photographer": "X",
            "download_url": f"u{pid}", "source_url": f"s{pid}",
            "width": w, "height": h}


def test_collect_walks_rungs_and_stops_at_want():
    ladder = fi.build_ladder(_row())  # pexels(ja), pexels(en), pixabay(ja), ...
    calls = []

    def pexels(term, lang):
        calls.append(("pexels", term, lang))
        return [_cand(1, 4000, 6000), _cand(2, 4000, 6000)]

    def pixabay(term, lang):
        calls.append(("pixabay", term, lang))
        return [_cand(3, 4000, 6000)]

    got = fi.collect_candidates(ladder, {"pexels": pexels, "pixabay": pixabay},
                                min_width=800, min_height=1200, want=3)
    # first pexels rung already yields 2, second pexels rung is called for the 3rd,
    # producing dupes (same ids) -> must reach pixabay for a distinct 3rd.
    ids = [c["photo_id"] for c in got]
    assert ids == ["1", "2", "3"]
    assert got[0]["provider"] == "pexels" and got[0]["search_lang"] == "ja-JP"
    assert got[2]["provider"] == "pixabay"


def test_collect_dedupes_by_provider_and_id():
    ladder = [{"provider": "pexels", "term": "a", "lang": "en"},
              {"provider": "pexels", "term": "b", "lang": "en"}]
    def pexels(term, lang):
        return [_cand(1, 4000, 6000)]  # same id both rungs
    got = fi.collect_candidates(ladder, {"pexels": pexels},
                                min_width=800, min_height=1200, want=3)
    assert len(got) == 1


def test_collect_applies_pixabay_effective_floor():
    # 4000x6000 pixabay -> effective ~853x1280, passes a 800x1200 floor.
    # 1200x1600 pixabay -> effective 960x1280, width 960 >= 800 passes;
    # 900x1000 pixabay -> effective unchanged (small), height 1000 < 1200 FAILS.
    ladder = [{"provider": "pixabay", "term": "a", "lang": "ja"}]
    def pixabay(term, lang):
        return [_cand(9, 900, 1000), _cand(8, 4000, 6000)]
    got = fi.collect_candidates(ladder, {"pixabay": pixabay},
                                min_width=800, min_height=1200, want=3)
    assert [c["photo_id"] for c in got] == ["8"]


def _split_image(width, height, busy_side):
    """A W×H image: one side richly multi-coloured, the other flat grey.
    busy_side in {'left','right','top','bottom'}."""
    img = Image.new("RGB", (width, height), (128, 128, 128))
    px = img.load()
    def busy(x, y):
        return ((x * 37 + y * 91) % 256, (x * 13) % 256, (y * 29) % 256)
    for y in range(height):
        for x in range(width):
            if busy_side == "left" and x < width // 2: px[x, y] = busy(x, y)
            if busy_side == "right" and x >= width // 2: px[x, y] = busy(x, y)
            if busy_side == "top" and y < height // 2: px[x, y] = busy(x, y)
            if busy_side == "bottom" and y >= height // 2: px[x, y] = busy(x, y)
    return img


def test_trim_split_drops_flatter_end():
    # counts: left end flat (1), right end busy (9) -> trim comes off the left.
    left, right = fi._trim_split([1, 1, 5, 9, 9], total_trim=2)
    assert (left, right) == (2, 0)


def test_smart_crop_reaches_target_ratio_trimming_columns():
    img = _split_image(600, 900, busy_side="right")  # wider than 9:19.5
    out = fi.smart_crop(img, 9, 19.5)
    ratio = out.width / out.height
    assert abs(ratio - (9 / 19.5)) < 0.02
    assert out.height == 900  # columns trimmed, height preserved


def _grey_fraction(im):
    px = fi._flat_data(im)
    return sum(1 for p in px if p == (128, 128, 128)) / len(px)


def test_smart_crop_prefers_the_busy_side():
    # busy on the right -> the flat left band is trimmed preferentially, so the
    # smart crop must retain LESS flat-grey area than a naive centre crop of the
    # same width would. (A degenerate centre-cropping smart_crop fails this.)
    img = _split_image(600, 900, busy_side="right")
    out = fi.smart_crop(img, 9, 19.5)
    tw = out.width
    left = (600 - tw) // 2
    centre = img.crop((left, 0, left + tw, 900))
    assert _grey_fraction(out) < _grey_fraction(centre)


def test_smart_crop_trims_rows_when_taller_than_target():
    img = _split_image(900, 3000, busy_side="top")  # taller than 9:19.5? 900/3000=0.3 < 0.46
    out = fi.smart_crop(img, 9, 19.5)
    ratio = out.width / out.height
    assert abs(ratio - (9 / 19.5)) < 0.02
    assert out.width == 900  # rows trimmed, width preserved


def test_resize_within_downscales_long_edge():
    img = Image.new("RGB", (2000, 4000))
    out = fi.resize_within(img, 2340)
    assert max(out.size) == 2340
    assert out.size == (1170, 2340)


def test_resize_within_never_upscales():
    img = Image.new("RGB", (600, 1280))
    out = fi.resize_within(img, 2340)
    assert out.size == (600, 1280)


def test_process_image_hits_target_ratio_and_max_edge():
    img = _split_image(3000, 4500, busy_side="right")
    out = fi.process_image(img, 9, 19.5, max_edge=2340)
    assert max(out.size) <= 2340
    assert abs(out.width / out.height - 9 / 19.5) < 0.02


def test_save_jpeg_writes_file(tmp_path=None):
    import tempfile
    d = Path(tempfile.mkdtemp())
    p = d / "x.jpg"
    fi.save_jpeg(Image.new("RGB", (100, 200), (10, 20, 30)), p, quality=82)
    assert p.exists() and p.stat().st_size > 0
    assert Image.open(p).size == (100, 200)


def _cand_row(date, idx, chosen="", provider="pexels", photographer="Aki"):
    return {"date": date, "image_id": fi.image_id_for(date), "candidate": str(idx),
            "chosen": chosen, "provider": provider, "search_term": "桜",
            "search_lang": "ja-JP", "photographer": photographer,
            "license_ja": "Pexels ライセンス", "license_en": "Pexels License",
            "title_ja": "桜", "title_en": "cherry blossom",
            "source_url": "s", "src_w": "1080", "src_h": "2340",
            "out_file": f"kigo-03-25__c{idx}.jpg"}


def test_candidate_row_shape():
    row = {"date": "2026-03-25", "kanji": "桜", "gloss_en": "cherry blossom",
           "reading_en": "sakura"}
    cand = {"provider": "pexels", "search_term": "桜", "search_lang": "ja-JP",
            "photographer": "Aki", "source_url": "s"}
    out = fi.candidate_row(row, cand, 1, "kigo-03-25__c1.jpg", 1080, 2340)
    assert set(out) == set(fi.CANDIDATE_COLUMNS)
    assert out["chosen"] == "" and out["candidate"] == 1
    assert out["title_ja"] == "桜" and out["title_en"] == "cherry blossom"
    assert out["license_en"] == "Pexels License"


def test_image_row_from_candidate_builds_attribution():
    out = fi.image_row_from_candidate(_cand_row("2026-03-25", 2, chosen="x"))
    assert out["date"] == "2026-03-25"
    assert out["image_id"] == "kigo-03-25"
    assert out["attribution_credit_en"] == "Photo: Aki / Pexels"
    assert out["attribution_credit_ja"] == "写真: Aki / Pexels"
    assert out["attribution_license_en"] == "Pexels License"
    assert set(out) == set(fi.IMAGE_COLUMNS)


def test_select_chosen_requires_exactly_one_per_date():
    rows = [_cand_row("2026-03-25", 1, chosen="x"), _cand_row("2026-03-25", 2)]
    picked = fi.select_chosen(rows)
    assert len(picked) == 1 and picked[0]["candidate"] == "1"


def test_select_chosen_errors_on_zero_or_multiple():
    for rows in (
        [_cand_row("2026-03-25", 1), _cand_row("2026-03-25", 2)],            # zero
        [_cand_row("2026-03-25", 1, "x"), _cand_row("2026-03-25", 2, "x")],  # two
    ):
        try:
            fi.select_chosen(rows)
        except ValueError as e:
            assert "2026-03-25" in str(e)
            continue
        raise AssertionError("expected ValueError")


def _write_spine(path):
    with path.open("w", newline="", encoding="utf-8") as f:
        w = _csv.DictWriter(f, fieldnames=["date", "kanji", "reading_ja",
                                           "reading_en", "gloss_en"])
        w.writeheader()
        w.writerow({"date": "2026-03-25", "kanji": "桜", "reading_ja": "さくら",
                    "reading_en": "sakura", "gloss_en": "cherry blossom"})


def test_cli_placeholder_writes_image_columns():
    d = Path(tempfile.mkdtemp())
    spine, out = d / "spine.csv", d / "images.csv"
    _write_spine(spine)
    r = subprocess.run([sys.executable, str(SCRIPT), "fetch", "--spine", str(spine),
                        "--out", str(out), "--placeholder"],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    rows = list(_csv.DictReader(out.open(encoding="utf-8")))
    assert rows[0]["image_id"] == "kigo-03-25"
    assert list(rows[0].keys()) == list(fi.IMAGE_COLUMNS)


def test_cli_select_end_to_end():
    d = Path(tempfile.mkdtemp())
    imgs = d / "downloads"; imgs.mkdir()
    # two candidate files + a candidates.csv marking c2
    for n in (1, 2):
        fi.save_jpeg(Image.new("RGB", (1080, 2340), (n, n, n)),
                     imgs / f"kigo-03-25__c{n}.jpg", 82)
    cand = d / "candidates.csv"
    with cand.open("w", newline="", encoding="utf-8") as f:
        w = _csv.DictWriter(f, fieldnames=fi.CANDIDATE_COLUMNS)
        w.writeheader()
        w.writerow(_cand_row("2026-03-25", 1))
        w.writerow(_cand_row("2026-03-25", 2, chosen="x"))
    out = d / "images.csv"
    r = subprocess.run([sys.executable, str(SCRIPT), "select",
                        "--candidates-in", str(cand), "--out", str(out),
                        "--out-images", str(imgs)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert (imgs / "kigo-03-25.jpg").exists()  # canonical copy of the chosen c2
    rows = list(_csv.DictReader(out.open(encoding="utf-8")))
    assert rows[0]["attribution_credit_en"] == "Photo: Aki / Pexels"


def test_cli_select_rejects_ambiguous_marking():
    d = Path(tempfile.mkdtemp()); imgs = d / "downloads"; imgs.mkdir()
    cand = d / "candidates.csv"
    with cand.open("w", newline="", encoding="utf-8") as f:
        w = _csv.DictWriter(f, fieldnames=fi.CANDIDATE_COLUMNS); w.writeheader()
        w.writerow(_cand_row("2026-03-25", 1))  # zero chosen
    r = subprocess.run([sys.executable, str(SCRIPT), "select",
                        "--candidates-in", str(cand), "--out", str(d / "o.csv"),
                        "--out-images", str(imgs)], capture_output=True, text=True)
    assert r.returncode != 0
    assert "2026-03-25" in r.stderr


def test_readme_documents_two_phase_and_pillow():
    text = README.read_text(encoding="utf-8")
    assert "fetch_images.py fetch" in text
    assert "fetch_images.py select" in text
    assert "candidates.csv" in text
    assert "Pillow" in text
    assert "chosen" in text  # the review column


if __name__ == "__main__":
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print("ALL PASS")
