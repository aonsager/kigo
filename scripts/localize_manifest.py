#\!/usr/bin/env python3
"""
localize_manifest.py — Adds English localization fields to every Daily Map entry
in Resources/manifest.json.

For each of the 365 Daily Map entries, adds:
  - reading.en: Hepburn romaji derived from reading.ja
  - description.en: copy of description.ja (already English text with a date)
  - attribution.title.en: "Season Kigo"
  - attribution.credit.en: "Unknown photographer"
  - attribution.license.en: "Public domain"

Usage (run from repo root):
    python3 scripts/localize_manifest.py
"""

import json
import os

# Hiragana -> Romaji table (Hepburn). Multi-char sequences first.
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
        # っ doubles next consonant
        if char == "っ":
            if i + 1 < len(text):
                # Try digraph
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
        # Try digraph
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


def localize_entry(entry: dict) -> None:
    entry["reading"]["en"] = hiragana_to_romaji(entry["reading"]["ja"])
    entry["description"]["en"] = entry["description"]["ja"]
    entry["attribution"]["title"]["en"] = "Season Kigo"
    entry["attribution"]["credit"]["en"] = "Unknown photographer"
    entry["attribution"]["license"]["en"] = "Public domain"


def main() -> None:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    manifest_path = os.path.join(repo_root, "Resources", "manifest.json")
    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)
    count = 0
    for key, entry in manifest["dailyMap"].items():
        localize_entry(entry)
        count += 1
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"Localized {count} daily map entries in {manifest_path}")


if __name__ == "__main__":
    main()
