#!/usr/bin/env python3
"""
generate_daily_map.py — Regenerates Resources/manifest.json with a full 366-entry Daily Map.

Usage (run from repo root):
    python3 scripts/generate_daily_map.py

The script is fully deterministic: no Date.now(), no random. Running it twice
produces byte-identical output. The existing single 06-12 菖蒲 entry is preserved
verbatim; all other entries are generated from seasonal templates.

Output: Resources/manifest.json (pretty-printed, keys sorted for stable diffs)
"""

import json
import os
import sys

# ---------------------------------------------------------------------------
# Rich entries — real kigo where we have them, otherwise plausible seasonal words.
# Keyed by MM-DD. The existing slice-8 entry is included here unchanged.
# ---------------------------------------------------------------------------
RICH_ENTRIES: dict[str, dict] = {
    # Existing real entry from slice #8 — keep verbatim
    "06-12": {
        "kanji": "菖蒲",
        "reading": "しょうぶ",
        "description": "Sweet flag — the blade-like iris leaves used in summer purification rites, placed in baths on Tango no Sekku.",
        "imageId": "ayame-06-12",
    },
    # A selection of well-known seasonal words by month
    # January
    "01-01": {
        "kanji": "初日の出",
        "reading": "はつひので",
        "description": "The first sunrise of the New Year, greeted from hilltops and shorelines across Japan.",
        "imageId": "kigo-01-01",
    },
    "01-07": {
        "kanji": "七草",
        "reading": "ななくさ",
        "description": "Seven spring herbs — seri, nazuna, gogyo, hakobera, hotokenoza, suzuna, suzushiro — eaten in rice porridge for health.",
        "imageId": "kigo-01-07",
    },
    "01-15": {
        "kanji": "小正月",
        "reading": "こしょうがつ",
        "description": "Little New Year, marked by rice-cake decoration and the burning of New Year ornaments at dawn.",
        "imageId": "kigo-01-15",
    },
    # February
    "02-03": {
        "kanji": "節分",
        "reading": "せつぶん",
        "description": "The eve of the first day of spring; roasted soybeans are scattered to drive out evil and invite good fortune.",
        "imageId": "kigo-02-03",
    },
    "02-04": {
        "kanji": "立春",
        "reading": "りっしゅん",
        "description": "First day of spring in the traditional calendar; plum blossoms begin to open in sheltered valleys.",
        "imageId": "kigo-02-04",
    },
    "02-11": {
        "kanji": "梅",
        "reading": "うめ",
        "description": "Plum blossom — the harbinger of spring, prized for its fragrance before the cherry unfurls.",
        "imageId": "kigo-02-11",
    },
    "02-29": {
        "kanji": "閏日",
        "reading": "うるうび",
        "description": "Leap day — the extra calendar day inserted every four years to reconcile the solar year with the Gregorian count.",
        "imageId": "kigo-02-29",
    },
    # March
    "03-03": {
        "kanji": "雛祭り",
        "reading": "ひなまつり",
        "description": "Doll Festival — tiered displays of imperial court dolls celebrate girls' happiness and good health.",
        "imageId": "kigo-03-03",
    },
    "03-21": {
        "kanji": "春分",
        "reading": "しゅんぶん",
        "description": "Spring equinox — day and night of equal length; ancestral graves are visited during Higan week.",
        "imageId": "kigo-03-21",
    },
    # April
    "04-01": {
        "kanji": "花見",
        "reading": "はなみ",
        "description": "Cherry-blossom viewing — friends and families gather beneath blossoming trees for food, drink, and seasonal joy.",
        "imageId": "kigo-04-01",
    },
    "04-08": {
        "kanji": "花祭り",
        "reading": "はなまつり",
        "description": "Buddha's birthday; temples erect flower-draped shrines and sweet tea is poured over a small Buddha statue.",
        "imageId": "kigo-04-08",
    },
    # May
    "05-05": {
        "kanji": "端午の節句",
        "reading": "たんごのせっく",
        "description": "Children's Day; carp streamers fly from poles and families eat chimaki rice dumplings wrapped in bamboo.",
        "imageId": "kigo-05-05",
    },
    "05-21": {
        "kanji": "小満",
        "reading": "しょうまん",
        "description": "Grain Buds — the solar term when grains begin to fill and silkworms start to spin their cocoons.",
        "imageId": "kigo-05-21",
    },
    # June
    "06-01": {
        "kanji": "衣替え",
        "reading": "ころもがえ",
        "description": "The seasonal change of clothing from winter to summer weight, observed on the first day of June.",
        "imageId": "kigo-06-01",
    },
    "06-06": {
        "kanji": "蛍",
        "reading": "ほたる",
        "description": "Fireflies — their cold green light drifting over rice paddies and riverbanks on humid summer evenings.",
        "imageId": "kigo-06-06",
    },
    # July
    "07-07": {
        "kanji": "七夕",
        "reading": "たなばた",
        "description": "Star Festival — wishes written on tanzaku paper strips and hung from bamboo under the summer night sky.",
        "imageId": "kigo-07-07",
    },
    "07-23": {
        "kanji": "大暑",
        "reading": "たいしょ",
        "description": "Great Heat — the peak of summer's intensity, when the sun blazes longest and cicadas cry without pause.",
        "imageId": "kigo-07-23",
    },
    # August
    "08-07": {
        "kanji": "立秋",
        "reading": "りっしゅう",
        "description": "First day of autumn in the traditional calendar; evenings begin to carry the faintest autumnal chill.",
        "imageId": "kigo-08-07",
    },
    "08-15": {
        "kanji": "盂蘭盆",
        "reading": "うらぼん",
        "description": "Obon — the mid-August festival when ancestral spirits are welcomed home with lanterns and bon odori dancing.",
        "imageId": "kigo-08-15",
    },
    # September
    "09-09": {
        "kanji": "重陽",
        "reading": "ちょうよう",
        "description": "Chrysanthemum Festival — chrysanthemum wine is drunk to ward off evil and pray for longevity.",
        "imageId": "kigo-09-09",
    },
    "09-23": {
        "kanji": "秋分",
        "reading": "しゅうぶん",
        "description": "Autumn equinox — equal day and night; the higan week of visits to ancestral graves in autumn gold.",
        "imageId": "kigo-09-23",
    },
    # October
    "10-10": {
        "kanji": "秋晴れ",
        "reading": "あきばれ",
        "description": "Autumn clarity — the crystalline blue skies and cool, dry air that typify October days in Japan.",
        "imageId": "kigo-10-10",
    },
    # November
    "11-03": {
        "kanji": "文化の日",
        "reading": "ぶんかのひ",
        "description": "Culture Day — clear November skies frame ceremonies honoring arts, science, and national heritage.",
        "imageId": "kigo-11-03",
    },
    "11-15": {
        "kanji": "七五三",
        "reading": "しちごさん",
        "description": "Children aged seven, five, and three visit shrines in formal dress to give thanks for their growth.",
        "imageId": "kigo-11-15",
    },
    # December
    "12-22": {
        "kanji": "冬至",
        "reading": "とうじ",
        "description": "Winter solstice — the year's shortest day; yuzu baths and pumpkin porridge ward off winter illness.",
        "imageId": "kigo-12-22",
    },
    "12-31": {
        "kanji": "大晦日",
        "reading": "おおみそか",
        "description": "New Year's Eve — temple bells toll 108 times at midnight to cleanse the worldly desires of the old year.",
        "imageId": "kigo-12-31",
    },
}

# ---------------------------------------------------------------------------
# Seasonal templates: month → (kanji, reading, description_template)
# These supply generated entries for days that have no rich entry.
# Description templates use {month} and {day} for deterministic variation.
# ---------------------------------------------------------------------------
MONTHLY_TEMPLATES = {
    1:  ("冬の日", "ふゆのひ",
         "A midwinter day in the first month — cold air and pale sun mark the depths of the season."),
    2:  ("春の兆し", "はるのきざし",
         "Early hints of spring stir in the second month, as buds swell on sheltered plum branches."),
    3:  ("春の暖かさ", "はるのあたたかさ",
         "Warmth returns in the third month; the earth softens and migratory birds arrive from the south."),
    4:  ("春雨", "はるさめ",
         "Spring rain falls softly in the fourth month, nurturing new growth on hillsides and in gardens."),
    5:  ("緑の風", "みどりのかぜ",
         "Fresh green leaves fill the fifth month with a cool, fragrant breeze across rice paddies and parks."),
    6:  ("梅雨", "つゆ",
         "The rainy season settles over the sixth month, bringing steady grey skies and a lush, humid quiet."),
    7:  ("夏の盛り", "なつのさかり",
         "High summer blazes in the seventh month; cicadas cry from every tree in the midday heat."),
    8:  ("晩夏", "ばんか",
         "Late summer lingers in the eighth month; evenings cool slightly and the Milky Way sharpens overhead."),
    9:  ("秋風", "あきかぜ",
         "Autumn winds arrive in the ninth month, carrying the scent of ripening rice and drying persimmons."),
    10: ("紅葉", "こうよう",
         "Maple leaves blaze red and gold in the tenth month, drawing crowds to mountain paths and temple gardens."),
    11: ("晩秋", "ばんしゅう",
         "Late autumn deepens in the eleventh month; bare branches frame pale skies above fallen leaf carpets."),
    12: ("冬の訪れ", "ふゆのおとずれ",
         "Winter arrives in the twelfth month; frost glitters at dawn and the year draws quietly toward its close."),
}


def generate_entry(month: int, day: int) -> dict:
    """Return a DailyMapEntry dict for the given month/day, using rich data or a template."""
    key = f"{month:02d}-{day:02d}"
    if key in RICH_ENTRIES:
        return RICH_ENTRIES[key]

    kanji, reading, description = MONTHLY_TEMPLATES[month]
    # Append the date to ensure the description is always ≥20 chars and uniquely identifies the day
    full_description = f"{description} ({key})"
    return {
        "kanji": kanji,
        "reading": reading,
        "description": full_description,
        "imageId": f"kigo-{key}",
    }


def build_daily_map() -> dict[str, dict]:
    """Generate all 366 MM-DD entries for a perennial calendar (using 2000 as leap year base)."""
    days_in_month = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    daily_map: dict[str, dict] = {}
    for month in range(1, 13):
        for day in range(1, days_in_month[month - 1] + 1):
            key = f"{month:02d}-{day:02d}"
            daily_map[key] = generate_entry(month, day)
    return daily_map


def main() -> None:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    manifest_path = os.path.join(repo_root, "Resources", "manifest.json")

    # Load existing manifest to preserve ko and sekki arrays unchanged
    with open(manifest_path, encoding="utf-8") as f:
        existing = json.load(f)

    daily_map = build_daily_map()

    # Validate count before writing
    assert len(daily_map) == 366, f"Expected 366 entries, got {len(daily_map)}"
    assert "02-29" in daily_map, "Missing 02-29 leap day"

    manifest = {
        "schemaVersion": existing.get("schemaVersion", "1.0"),
        "dailyMap": dict(sorted(daily_map.items())),  # stable sort by MM-DD
        "ko": existing.get("ko", []),
        "sekki": existing.get("sekki", []),
    }

    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")  # POSIX trailing newline

    print(f"Wrote {len(daily_map)} daily map entries to {manifest_path}")


if __name__ == "__main__":
    main()
