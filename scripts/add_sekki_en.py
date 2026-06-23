#!/usr/bin/env python3
"""
add_sekki_en.py — Adds reading.en (Hepburn romaji), gloss.en (English phrase),
and description.en (English placeholder) to every Sekki entry in
Resources/manifest.json.

Usage (run from repo root):
    python3 scripts/add_sekki_en.py
"""

import json
import os

# Re-use the same hiragana→romaji conversion as localize_manifest.py / add_ko_en.py
HIRAGANA_TO_ROMAJI = [
    # Digraphs
    ("きゃ", "kya"), ("きゅ", "kyu"), ("きょ", "kyo"),
    ("しゃ", "sha"), ("しゅ", "shu"), ("しょ", "sho"),
    ("ちゃ", "cha"), ("ちゅ", "chu"), ("ちょ", "cho"),
    ("にゃ", "nya"), ("にゅ", "nyu"), ("にょ", "nyo"),
    ("ひゃ", "hya"), ("ひゅ", "hyu"), ("ひょ", "hyo"),
    ("みゃ", "mya"), ("みゅ", "myu"), ("みょ", "myo"),
    ("りゃ", "rya"), ("りゅ", "ryu"), ("りょ", "ryo"),
    ("ぎゃ", "gya"), ("ぎゅ", "gyu"), ("ぎょ", "gyo"),
    ("じゃ", "ja"),  ("じゅ", "ju"),  ("じょ", "jo"),
    ("びゃ", "bya"), ("びゅ", "byu"), ("びょ", "byo"),
    ("ぴゃ", "pya"), ("ぴゅ", "pyu"), ("ぴょ", "pyo"),
    # Single kana
    ("あ", "a"),  ("い", "i"),  ("う", "u"),  ("え", "e"),  ("お", "o"),
    ("か", "ka"), ("き", "ki"), ("く", "ku"), ("け", "ke"), ("こ", "ko"),
    ("さ", "sa"), ("し", "shi"),("す", "su"), ("せ", "se"), ("そ", "so"),
    ("た", "ta"), ("ち", "chi"),("つ", "tsu"),("て", "te"), ("と", "to"),
    ("な", "na"), ("に", "ni"), ("ぬ", "nu"), ("ね", "ne"), ("の", "no"),
    ("は", "ha"), ("ひ", "hi"), ("ふ", "fu"), ("へ", "he"), ("ほ", "ho"),
    ("ま", "ma"), ("み", "mi"), ("む", "mu"), ("め", "me"), ("も", "mo"),
    ("や", "ya"), ("ゆ", "yu"), ("よ", "yo"),
    ("ら", "ra"), ("り", "ri"), ("る", "ru"), ("れ", "re"), ("ろ", "ro"),
    ("わ", "wa"), ("ゐ", "i"),  ("ゑ", "e"),  ("を", "o"),
    ("ん", "n"),
    ("が", "ga"), ("ぎ", "gi"), ("ぐ", "gu"), ("げ", "ge"), ("ご", "go"),
    ("ざ", "za"), ("じ", "ji"), ("ず", "zu"), ("ぜ", "ze"), ("ぞ", "zo"),
    ("だ", "da"), ("ぢ", "ji"), ("づ", "zu"), ("で", "de"), ("ど", "do"),
    ("ば", "ba"), ("び", "bi"), ("ぶ", "bu"), ("べ", "be"), ("ぼ", "bo"),
    ("ぱ", "pa"), ("ぴ", "pi"), ("ぷ", "pu"), ("ぺ", "pe"), ("ぽ", "po"),
    # Small vowels
    ("ぁ", "a"), ("ぃ", "i"), ("ぅ", "u"), ("ぇ", "e"), ("ぉ", "o"),
    ("ゃ", "ya"),("ゅ", "yu"),("ょ", "yo"),
]

LONG_VOWEL_MAP = [
    ("ou", "ō"),
    ("oo", "ō"),
    ("uu", "ū"),
]


def hiragana_to_romaji(text: str) -> str:
    result = ""
    i = 0
    while i < len(text):
        char = text[i]
        if char == "っ":
            if i + 1 < len(text):
                found = False
                if i + 2 < len(text):
                    digraph = text[i+1] + text[i+2]
                    for hira, roma in HIRAGANA_TO_ROMAJI:
                        if hira == digraph:
                            result += roma[0]
                            found = True
                            break
                if not found:
                    next_char = text[i+1]
                    for hira, roma in HIRAGANA_TO_ROMAJI:
                        if hira == next_char and len(hira) == 1:
                            result += roma[0]
                            found = True
                            break
                if not found:
                    result += "t"
            i += 1
            continue
        matched = False
        if i + 1 < len(text):
            digraph = text[i] + text[i+1]
            for hira, roma in HIRAGANA_TO_ROMAJI:
                if hira == digraph:
                    result += roma
                    i += 2
                    matched = True
                    break
        if not matched:
            for hira, roma in HIRAGANA_TO_ROMAJI:
                if hira == char and len(hira) == 1:
                    result += roma
                    i += 1
                    matched = True
                    break
        if not matched:
            result += char
            i += 1
    for pattern, replacement in LONG_VOWEL_MAP:
        result = result.replace(pattern, replacement)
    return result


# English gloss and description for each of the 24 sekki, keyed by kanji.
# Gloss: short English phrase for the solar term name.
# Description: English placeholder description (J2 — placeholder quality for human review).
SEKKI_EN: dict[str, tuple[str, str]] = {
    "立春": (
        "Start of Spring",
        "The first solar term of the year, marking the calendrical beginning of spring. "
        "Days gradually lengthen and the air begins to soften, even as cold lingers.",
    ),
    "雨水": (
        "Rain Water",
        "Snow and ice give way to rain as temperatures rise. "
        "The snowmelt feeds the rivers and the soil begins to absorb moisture in preparation for planting.",
    ),
    "啓蟄": (
        "Awakening of Insects",
        "Underground creatures stirred by the warming earth begin to emerge from their winter burrows. "
        "The landscape slowly comes back to life with the first signs of insect activity.",
    ),
    "春分": (
        "Spring Equinox",
        "Day and night are of equal length as the sun crosses the celestial equator. "
        "A holiday of ancestor veneration in Japan, and the midpoint of spring.",
    ),
    "清明": (
        "Clear and Bright",
        "The air is fresh and clear, and the natural world is vivid and full of color. "
        "Flowers bloom abundantly and birds sing through the bright spring days.",
    ),
    "穀雨": (
        "Grain Rains",
        "Rains nourish the newly sown grain crops across the fields. "
        "This moisture is essential for the seedlings that will grow through the warm season ahead.",
    ),
    "立夏": (
        "Start of Summer",
        "The calendrical beginning of summer. The sun's warmth becomes pronounced, "
        "and the green of trees and paddies deepens as the growing season fully opens.",
    ),
    "小満": (
        "Grain Buds",
        "Crops fill out and begin to ripen under the strengthening sun. "
        "The days grow longer and the land is lush with the promise of the coming harvest.",
    ),
    "芒種": (
        "Grain in Ear",
        "The time to plant rice and barley, whose grain heads bear awns. "
        "Farmers are busy in the paddies as the rainy season approaches the Japanese archipelago.",
    ),
    "夏至": (
        "Summer Solstice",
        "The longest day of the year; the sun reaches its highest arc in the sky. "
        "From this point, days shorten as summer heat continues to intensify.",
    ),
    "小暑": (
        "Minor Heat",
        "Temperatures climb and the heat of summer becomes fully felt. "
        "Cicadas begin their chorus and the humidity of the Japanese summer settles in.",
    ),
    "大暑": (
        "Major Heat",
        "The hottest period of the year. Intense heat and humidity dominate, "
        "and people seek shade, cool water, and relief from the sweltering midsummer days.",
    ),
    "立秋": (
        "Start of Autumn",
        "Though the heat often continues, this marks the calendrical start of autumn. "
        "The quality of light shifts subtly, and evenings bring the first hints of coolness.",
    ),
    "処暑": (
        "End of Heat",
        "The oppressive summer heat begins to ease as the sun's strength wanes. "
        "Mornings and evenings feel noticeably cooler, signaling the approach of true autumn.",
    ),
    "白露": (
        "White Dew",
        "Dew glistens white on grasses in the cool of early morning. "
        "The air carries the crispness of autumn and the landscape takes on golden hues.",
    ),
    "秋分": (
        "Autumn Equinox",
        "Day and night are again equal in length as the sun crosses the equator southward. "
        "A holiday of ancestor remembrance in Japan, and the midpoint of autumn.",
    ),
    "寒露": (
        "Cold Dew",
        "Dew turns cold and the air carries a definite chill before dawn. "
        "Chrysanthemums bloom and migrating birds pass through on their southward journey.",
    ),
    "霜降": (
        "Frost's Descent",
        "The first frosts of the year settle on fields and rooftops overnight. "
        "Leaves turn brilliant red and gold before beginning to fall in earnest.",
    ),
    "立冬": (
        "Start of Winter",
        "The calendrical beginning of winter. Cold winds arrive and the landscape grows bare. "
        "People begin to prepare their homes and wardrobes for the coming cold months.",
    ),
    "小雪": (
        "Minor Snow",
        "Light snowfalls dust the mountains and some lowland areas for the first time. "
        "The sky is often overcast and the days grow noticeably shorter.",
    ),
    "大雪": (
        "Major Snow",
        "Heavy snowfalls blanket the land and the mountains are deep with snow. "
        "Bears retreat to their dens and the countryside settles into the quiet of winter.",
    ),
    "冬至": (
        "Winter Solstice",
        "The shortest day of the year; the sun is at its lowest arc. "
        "In Japan, people eat kabocha pumpkin and take yuzu-scented baths to ward off illness.",
    ),
    "小寒": (
        "Minor Cold",
        "The cold deepens and mornings are bitingly frigid. "
        "This marks the beginning of the coldest stretch of the year, leading into Daikan.",
    ),
    "大寒": (
        "Major Cold",
        "The coldest period of the year. Ice forms on ponds and rivers and the ground is hard with frost. "
        "Traditional arts such as cold-water practice and miso brewing take place during this time.",
    ),
}


def main() -> None:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    manifest_path = os.path.join(repo_root, "Resources", "manifest.json")
    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)

    sekki_entries = manifest.get("sekki", [])
    count = 0
    missing = []
    for entry in sekki_entries:
        kanji = entry.get("kanji", "")
        reading_ja = entry.get("reading", {}).get("ja", "")

        # reading.en — Hepburn romaji from the hiragana reading
        entry["reading"]["en"] = hiragana_to_romaji(reading_ja)

        # gloss.en and description.en from the lookup table
        data = SEKKI_EN.get(kanji)
        if data:
            gloss_en, desc_en = data
            entry["gloss"]["en"] = gloss_en
            entry["description"]["en"] = desc_en
        else:
            missing.append(kanji)

        count += 1

    if missing:
        print(f"WARNING: no English data for {len(missing)} sekki entries: {missing}")
    else:
        print(f"Added EN fields to all {count} sekki entries.")

    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Wrote updated manifest to {manifest_path}")


if __name__ == "__main__":
    main()
