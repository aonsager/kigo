#!/usr/bin/env python3
"""
add_ko_en.py — Adds reading.en (Hepburn romaji) and description.en (English one-liner)
to every Kō entry in Resources/manifest.json.

The kō.gloss field is already English and is left untouched.

Usage (run from repo root):
    python3 scripts/add_ko_en.py
"""

import json
import os

# Re-use the same hiragana→romaji conversion as localize_manifest.py
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


# One-liner English descriptions for each of the 72 kō, keyed by kanji.
# These are placeholder-quality descriptions for human content review (J2).
KO_DESCRIPTIONS_EN = {
    "東風解凍": "The spring east wind begins to thaw rivers and lakes.",
    "黄鶯睍睆": "Bush warblers sing their first clear notes from the mountain slopes.",
    "魚上氷": "Fish rise toward the surface as ice melts in the rivers.",
    "土脉潤起": "Moisture stirs in the soil as warmth slowly returns to the earth.",
    "霞始靆": "Haze drifts gently across the fields at the edge of spring.",
    "草木萌動": "Buds swell on trees and fresh green shoots push through the soil.",
    "蟄虫啓戸": "Insects hibernating underground rouse themselves and open their burrows.",
    "桃始笑": "Peach trees break into their first delicate blossoms of the season.",
    "菜虫化蝶": "Caterpillars that fed on winter greens emerge as early butterflies.",
    "雀始巣": "Sparrows begin gathering straws and twigs to build their nests.",
    "桜始開": "The first cherry blossoms open, marking the beloved arrival of spring.",
    "雷乃発声": "Thunder rolls for the first time after the long winter silence.",
    "玄鳥至": "Swallows return from the south, swooping low over the eaves.",
    "鴻雁北": "Wild geese lift off and fly northward to their summer breeding grounds.",
    "虹始見": "The first rainbow of the year arches over the spring rain showers.",
    "葭始生": "Reeds push fresh green shoots up through the mud at the water's edge.",
    "霜止出苗": "Morning frosts cease and seedlings are set out in flooded paddies.",
    "牡丹華": "Tree peonies open their lush, heavy blossoms in the late-spring garden.",
    "蛙始鳴": "Frogs begin calling at dusk from the newly flooded rice paddies.",
    "蚯蚓出": "Earthworms surface through rain-softened soil, enriching the earth.",
    "竹笋生": "Bamboo shoots surge up overnight, sometimes several centimeters in a day.",
    "蚕起食桑": "Silkworms hatch from their winter eggs and begin feeding on mulberry leaves.",
    "紅花栄": "Safflowers burst into brilliant orange-red bloom under the early summer sun.",
    "麦秋至": "The wheat fields ripen to gold, ready for the early harvest.",
    "螳螂生": "Praying mantis eggs hatch and the tiny nymphs scatter into the grasses.",
    "腐草為螢": "Fireflies emerge at twilight, their cold light flickering above the meadows.",
    "梅子黄": "Plums swell and ripen to yellow-green, ready for pickling into umeboshi.",
    "乃東枯": "Self-heal, which bloomed in the cold, withers back as summer deepens.",
    "菖蒲華": "Iris flowers open beside still water, their purple petals vivid in the rain.",
    "半夏生": "Crow-dipper sprouts as the rainy season peaks; farmers pause fieldwork.",
    "温風至": "Warm, humid summer winds begin to blow steadily from the south.",
    "蓮始開": "Lotus blossoms unfurl at dawn on calm ponds, closing again by noon.",
    "鷹乃学習": "Young hawks practice circling and stooping, learning the art of the hunt.",
    "桐始結花": "Paulownia trees set their first seed pods after the blossoms have fallen.",
    "土潤溽暑": "The ground is damp and the air heavy with the sultry heat of midsummer.",
    "大雨時行": "Sudden heavy downpours sweep across the land at unpredictable intervals.",
    "涼風至": "A refreshing cool breeze arrives, hinting at the end of summer's heat.",
    "寒蝉鳴": "Higurashi cicadas begin their melancholy dusk chorus in the hill forests.",
    "蒙霧升降": "Thick mist rolls in and out, blurring the boundary of mountain and sky.",
    "綿柎開": "Cotton bolls split open, revealing tufts of white fiber in the autumn fields.",
    "天地始粛": "The air turns crisp; heaven and earth take on the stillness of early autumn.",
    "禾乃登": "Rice and grain stand tall and heavy-headed, ripening under the harvest moon.",
    "草露白": "White dew glistens on blades of grass each morning as nights grow cooler.",
    "鶺鴒鳴": "Wagtails bob along streamsides, their piping calls clear in the autumn air.",
    "玄鳥去": "Swallows gather on wires and then depart southward before the cold arrives.",
    "雷乃収声": "The thunder that rang all summer finally falls silent with the autumn chill.",
    "蟄虫坏戸": "Insects begin to seal their burrows shut as they prepare for winter sleep.",
    "水始涸": "Waters in the paddies and shallows begin to recede and dry as autumn deepens.",
    "鴻雁来": "Wild geese arrive from the north, filling the wetlands with their clamor.",
    "菊花開": "Chrysanthemums bloom in shades of gold and white, the emblem of autumn.",
    "蟋蟀在戸": "Crickets chirp at the doorstep through the long, cooling autumn nights.",
    "霜始降": "The first frost of the season settles overnight on rooftops and fields.",
    "霎時施": "Brief, fine autumn showers drift through intermittently, barely wetting the ground.",
    "楓蔦黄": "Maple leaves turn crimson and ivy vines flame yellow along stone walls.",
    "山茶始開": "Camellia buds open in the garden as other flowers retreat before the cold.",
    "地始凍": "The ground freezes hard for the first time, crunching underfoot at dawn.",
    "金盞香": "Narcissus blooms perfume the winter garden with their quiet, sweet fragrance.",
    "虹蔵不見": "Rainbows vanish from the sky as winter clouds thicken and sunlight dims.",
    "朔風払葉": "The north wind tears the last clinging leaves from bare branches.",
    "橘始黄": "Native tachibana citrus begins to turn yellow on the branch in early winter.",
    "閉塞成冬": "The sky closes in, the earth goes silent, and winter fully settles.",
    "熊蟄穴": "Bears grow drowsy, find their dens, and retreat into a deep winter sleep.",
    "鱖魚群": "Salmon crowd together and push upstream to their spawning grounds.",
    "乃東生": "Self-heal sprouts anew in the cold earth, one of the few plants of midwinter.",
    "麋角解": "Elk shed their heavy antlers; the bones of the old year fall away.",
    "雪下出麦": "Wheat shoots push up green through the blanket of snow on the fields.",
    "芹乃栄": "Japanese parsley flourishes in cold, clear streams, crisp and fragrant.",
    "水泉動": "Underground springs begin to stir and flow, sensing the first warmth below.",
    "雉始雊": "Male pheasants begin their booming calls across the frosty winter fields.",
    "款冬華": "Butterbur sends up its pale flowers before any leaf appears, defying the cold.",
    "水沢腹堅": "Ice thickens into solid sheets across ponds and marshes in the deep cold.",
    "鶏始乳": "Hens feel the lengthening light and begin to lay eggs again after winter.",
}


def main() -> None:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    manifest_path = os.path.join(repo_root, "Resources", "manifest.json")
    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)

    ko_entries = manifest.get("ko", [])
    count = 0
    missing_desc = []
    for entry in ko_entries:
        kanji = entry.get("kanji", "")
        reading_ja = entry.get("reading", {}).get("ja", "")

        # reading.en — Hepburn romaji from the hiragana reading
        entry["reading"]["en"] = hiragana_to_romaji(reading_ja)

        # description.en — English one-liner from the lookup table
        desc_en = KO_DESCRIPTIONS_EN.get(kanji)
        if desc_en:
            entry["description"]["en"] = desc_en
        else:
            missing_desc.append(kanji)

        count += 1

    if missing_desc:
        print(f"WARNING: no English description for {len(missing_desc)} kō entries: {missing_desc}")

    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Added EN fields to {count} kō entries in {manifest_path}")
    if not missing_desc:
        print("All 72 entries have reading.en and description.en.")


if __name__ == "__main__":
    main()
