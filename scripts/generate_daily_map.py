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


# ---------------------------------------------------------------------------
# Canonical 24 Sekki (二十四節気) — stable romaji ids, canonical order.
# Each entry carries a required Japanese gloss and description (ADR 0014, slice #98).
# Placeholder prose is intentional — well-formedness, not literary quality, is gated.
# The localized-text shape is {"ja": "…"} (EN omitted; will be added in a later slice).
# ---------------------------------------------------------------------------
SEKKI_DATA: list[dict] = [
    {
        "id": "risshun", "kanji": "立春", "reading": "りっしゅん",
        "gloss": {"ja": "春の始まり"},
        "description": {"ja": "太陽が黄経315度に達する日。春の気配が感じられ始める二十四節気の最初の節気。"},
    },
    {
        "id": "usui", "kanji": "雨水", "reading": "うすい",
        "gloss": {"ja": "雨と雪解け"},
        "description": {"ja": "太陽が黄経330度に達する日。雪が雨に変わり、氷が溶け始める時期。"},
    },
    {
        "id": "keichitsu", "kanji": "啓蟄", "reading": "けいちつ",
        "gloss": {"ja": "虫が土から出る"},
        "description": {"ja": "太陽が黄経345度に達する日。冬ごもりしていた虫が地中から這い出てくる時期。"},
    },
    {
        "id": "shunbun", "kanji": "春分", "reading": "しゅんぶん",
        "gloss": {"ja": "昼と夜が等しい春の日"},
        "description": {"ja": "太陽が黄経0度（春分点）に達する日。昼と夜の長さが等しくなる。"},
    },
    {
        "id": "seimei", "kanji": "清明", "reading": "せいめい",
        "gloss": {"ja": "清らかで明るい"},
        "description": {"ja": "太陽が黄経15度に達する日。万物が清らかで生き生きとする時期。"},
    },
    {
        "id": "kokuu", "kanji": "穀雨", "reading": "こくう",
        "gloss": {"ja": "穀物を育てる雨"},
        "description": {"ja": "太陽が黄経30度に達する日。穀物の成長を助ける春の雨が降る時期。"},
    },
    {
        "id": "rikka", "kanji": "立夏", "reading": "りっか",
        "gloss": {"ja": "夏の始まり"},
        "description": {"ja": "太陽が黄経45度に達する日。夏の気配が感じられ始める時期。"},
    },
    {
        "id": "shouman", "kanji": "小満", "reading": "しょうまん",
        "gloss": {"ja": "草木が満ちてくる"},
        "description": {"ja": "太陽が黄経60度に達する日。草木が成長し、万物が満ちてくる時期。"},
    },
    {
        "id": "boshu", "kanji": "芒種", "reading": "ぼうしゅ",
        "gloss": {"ja": "芒のある穀物を蒔く"},
        "description": {"ja": "太陽が黄経75度に達する日。稲や麦など芒のある穀物を種まきする時期。"},
    },
    {
        "id": "geshi", "kanji": "夏至", "reading": "げし",
        "gloss": {"ja": "昼が最も長い日"},
        "description": {"ja": "太陽が黄経90度に達する日。北半球で昼の時間が最も長くなる。"},
    },
    {
        "id": "shousho", "kanji": "小暑", "reading": "しょうしょ",
        "gloss": {"ja": "暑さが増してくる"},
        "description": {"ja": "太陽が黄経105度に達する日。本格的な暑さが始まる時期。"},
    },
    {
        "id": "taisho", "kanji": "大暑", "reading": "たいしょ",
        "gloss": {"ja": "最も暑い時期"},
        "description": {"ja": "太陽が黄経120度に達する日。一年で最も暑さが厳しい時期。"},
    },
    {
        "id": "risshu", "kanji": "立秋", "reading": "りっしゅう",
        "gloss": {"ja": "秋の始まり"},
        "description": {"ja": "太陽が黄経135度に達する日。暦の上では秋が始まる。"},
    },
    {
        "id": "shosho", "kanji": "処暑", "reading": "しょしょ",
        "gloss": {"ja": "暑さが和らぐ"},
        "description": {"ja": "太陽が黄経150度に達する日。暑さが峠を越えて和らいでくる時期。"},
    },
    {
        "id": "hakuro", "kanji": "白露", "reading": "はくろ",
        "gloss": {"ja": "白い露が降りる"},
        "description": {"ja": "太陽が黄経165度に達する日。草木に白い露が宿り始める時期。"},
    },
    {
        "id": "shubun", "kanji": "秋分", "reading": "しゅうぶん",
        "gloss": {"ja": "昼と夜が等しい秋の日"},
        "description": {"ja": "太陽が黄経180度（秋分点）に達する日。昼と夜の長さが等しくなる。"},
    },
    {
        "id": "kanro", "kanji": "寒露", "reading": "かんろ",
        "gloss": {"ja": "冷たい露が降りる"},
        "description": {"ja": "太陽が黄経195度に達する日。露が冷たくなり、秋の深まりを感じる時期。"},
    },
    {
        "id": "soko", "kanji": "霜降", "reading": "そうこう",
        "gloss": {"ja": "霜が降りる"},
        "description": {"ja": "太陽が黄経210度に達する日。霜が降り始め、紅葉が深まる時期。"},
    },
    {
        "id": "rittou", "kanji": "立冬", "reading": "りっとう",
        "gloss": {"ja": "冬の始まり"},
        "description": {"ja": "太陽が黄経225度に達する日。暦の上では冬が始まる時期。"},
    },
    {
        "id": "shousetsu", "kanji": "小雪", "reading": "しょうせつ",
        "gloss": {"ja": "少し雪が降る"},
        "description": {"ja": "太陽が黄経240度に達する日。北国では雪が降り始める時期。"},
    },
    {
        "id": "taisetsu", "kanji": "大雪", "reading": "たいせつ",
        "gloss": {"ja": "雪が多く降る"},
        "description": {"ja": "太陽が黄経255度に達する日。本格的な雪の季節が訪れる時期。"},
    },
    {
        "id": "touji", "kanji": "冬至", "reading": "とうじ",
        "gloss": {"ja": "昼が最も短い日"},
        "description": {"ja": "太陽が黄経270度に達する日。北半球で昼の時間が最も短くなる。"},
    },
    {
        "id": "shoukan", "kanji": "小寒", "reading": "しょうかん",
        "gloss": {"ja": "寒さが厳しくなる"},
        "description": {"ja": "太陽が黄経285度に達する日。寒の入りで、本格的な寒さが始まる時期。"},
    },
    {
        "id": "daikan", "kanji": "大寒", "reading": "だいかん",
        "gloss": {"ja": "最も寒い時期"},
        "description": {"ja": "太陽が黄経300度に達する日。一年で最も寒さが厳しい時期。"},
    },
]

# ---------------------------------------------------------------------------
# Canonical 72 Kō (七十二候) — 3 per Sekki, in canonical almanac order.
# dateRange values are plausible ~5-day MM-DD windows (contiguity is slice #11).
# The boshu/shoko entry (first Kō of 芒種) preserves the existing dates from slice #9.
# Each entry carries a required Japanese description (ADR 0014, slice #99).
# Placeholder prose is intentional — well-formedness, not literary quality, is gated.
# ---------------------------------------------------------------------------
KO_DATA: list[dict] = [
    # 立春 risshun (~Feb 4)
    {"kanji": "東風解凍",   "reading": "はるかぜこおりをとく",       "gloss": "east wind thaws the ice",             "sekkiId": "risshun",   "dateRange": {"start": "02-04", "end": "02-08"}, "description": {"ja": "春の東風が川や湖の氷を解かし始める。寒さの中にも春の気配を感じる時期。"}},
    {"kanji": "黄鶯睍睆",   "reading": "うぐいすなく",               "gloss": "bush warblers sing in the mountains", "sekkiId": "risshun",   "dateRange": {"start": "02-09", "end": "02-13"}, "description": {"ja": "山でウグイスが鳴き始める。春の訪れを告げる澄んだ声が野山に響く。"}},
    {"kanji": "魚上氷",     "reading": "うおこおりをいずる",         "gloss": "fish emerge from under the ice",      "sekkiId": "risshun",   "dateRange": {"start": "02-14", "end": "02-18"}, "description": {"ja": "氷の解けた川で魚が水面近くに浮かび上がる。春の訪れを水中でも感じる頃。"}},
    # 雨水 usui (~Feb 19)
    {"kanji": "土脉潤起",   "reading": "つちのしょううるおいおこる", "gloss": "soil moisture stirs and rises",        "sekkiId": "usui",      "dateRange": {"start": "02-19", "end": "02-23"}, "description": {"ja": "大地が潤い始め、土の中の水分が動き出す。春雨が大地を柔らかくほぐす時期。"}},
    {"kanji": "霞始靆",     "reading": "かすみはじめてたなびく",     "gloss": "mist begins to drift",                "sekkiId": "usui",      "dateRange": {"start": "02-24", "end": "02-29"}, "description": {"ja": "春の霞が山や野に漂い始める。空気が湿り気を帯び、春らしい景色が広がる。"}},
    {"kanji": "草木萌動",   "reading": "そうもくめばえいずる",       "gloss": "plants and trees begin to bud",       "sekkiId": "usui",      "dateRange": {"start": "03-01", "end": "03-05"}, "description": {"ja": "草や木の芽が動き始め、大地に緑の気配が漂う。春の生命力が地上に現れる。"}},
    # 啓蟄 keichitsu (~Mar 6)
    {"kanji": "蟄虫啓戸",   "reading": "すごもりのむしとをひらく",   "gloss": "hibernating insects open their doors", "sekkiId": "keichitsu", "dateRange": {"start": "03-06", "end": "03-10"}, "description": {"ja": "冬ごもりしていた虫たちが土の戸を開けて這い出す。春の温もりが地中まで届く頃。"}},
    {"kanji": "桃始笑",     "reading": "ももはじめてさく",           "gloss": "peach blossoms first bloom",          "sekkiId": "keichitsu", "dateRange": {"start": "03-11", "end": "03-15"}, "description": {"ja": "桃の花が咲き始める。淡い桃色の花が春の野に明るさをもたらす時期。"}},
    {"kanji": "菜虫化蝶",   "reading": "なむしちょうとなる",         "gloss": "caterpillars become butterflies",     "sekkiId": "keichitsu", "dateRange": {"start": "03-16", "end": "03-20"}, "description": {"ja": "青虫が蛹から羽化し、蝶となって飛び始める。春の変容を象徴する美しい時期。"}},
    # 春分 shunbun (~Mar 21)
    {"kanji": "雀始巣",     "reading": "すずめはじめてすくう",       "gloss": "sparrows begin to nest",              "sekkiId": "shunbun",   "dateRange": {"start": "03-21", "end": "03-25"}, "description": {"ja": "雀が巣を作り始める。春分を過ぎ、鳥たちが繁殖の準備を始める頃。"}},
    {"kanji": "桜始開",     "reading": "さくらはじめてひらく",       "gloss": "cherry blossoms first open",          "sekkiId": "shunbun",   "dateRange": {"start": "03-26", "end": "03-30"}, "description": {"ja": "桜の花が開き始める。日本の春の象徴である桜の季節がいよいよ到来する。"}},
    {"kanji": "雷乃発声",   "reading": "かみなりすなわちこえをはっす","gloss": "thunder first rumbles",               "sekkiId": "shunbun",   "dateRange": {"start": "03-31", "end": "04-04"}, "description": {"ja": "春の雷が初めて鳴り響く。春の大気が活発になり、恵みの雨をもたらす合図。"}},
    # 清明 seimei (~Apr 5)
    {"kanji": "玄鳥至",     "reading": "つばめきたる",               "gloss": "swallows arrive",                     "sekkiId": "seimei",    "dateRange": {"start": "04-05", "end": "04-09"}, "description": {"ja": "ツバメが南から渡ってくる。軒先に巣を作り、夏の終わりまで人の暮らしに寄り添う。"}},
    {"kanji": "鴻雁北",     "reading": "こうがんきたへかえる",       "gloss": "wild geese fly north",                "sekkiId": "seimei",    "dateRange": {"start": "04-10", "end": "04-14"}, "description": {"ja": "雁が北の繁殖地へ帰っていく。冬の間日本に滞在していた渡り鳥との別れの時期。"}},
    {"kanji": "虹始見",     "reading": "にじはじめてあらわる",       "gloss": "rainbows first appear",               "sekkiId": "seimei",    "dateRange": {"start": "04-15", "end": "04-19"}, "description": {"ja": "春の雨上がりに虹が姿を現し始める。清明の空気に七色の橋がかかる美しい季節。"}},
    # 穀雨 kokuu (~Apr 20)
    {"kanji": "葭始生",     "reading": "あしはじめてしょうず",       "gloss": "reeds begin to sprout",               "sekkiId": "kokuu",     "dateRange": {"start": "04-20", "end": "04-24"}, "description": {"ja": "水辺の葦が芽吹き始める。湿地や川沿いに緑の新芽が顔を出す春の情景。"}},
    {"kanji": "霜止出苗",   "reading": "しもやんでなえいずる",       "gloss": "frost stops and seedlings emerge",    "sekkiId": "kokuu",     "dateRange": {"start": "04-25", "end": "04-29"}, "description": {"ja": "霜が降りなくなり、田植えの苗が育ち始める。農作業が本格的に始まる時期。"}},
    {"kanji": "牡丹華",     "reading": "ぼたんはなさく",             "gloss": "tree peonies bloom",                  "sekkiId": "kokuu",     "dateRange": {"start": "04-30", "end": "05-04"}, "description": {"ja": "牡丹の花が咲き誇る。百花の王とも呼ばれる豪華な花が春の庭を彩る。"}},
    # 立夏 rikka (~May 6)
    {"kanji": "蛙始鳴",     "reading": "かわずはじめてなく",         "gloss": "frogs begin to call",                 "sekkiId": "rikka",     "dateRange": {"start": "05-05", "end": "05-09"}, "description": {"ja": "カエルが田や水辺で鳴き始める。その声が夏の始まりを知らせる水辺の便り。"}},
    {"kanji": "蚯蚓出",     "reading": "みみずいずる",               "gloss": "earthworms emerge",                   "sekkiId": "rikka",     "dateRange": {"start": "05-10", "end": "05-14"}, "description": {"ja": "ミミズが地表に這い出てくる。大地が温まり、土の中の生き物も活動を始める頃。"}},
    {"kanji": "竹笋生",     "reading": "たけのこしょうず",           "gloss": "bamboo shoots sprout",                "sekkiId": "rikka",     "dateRange": {"start": "05-15", "end": "05-20"}, "description": {"ja": "竹の子が地面を割って勢いよく伸び出す。成長の速さが初夏の生命力を象徴する。"}},
    # 小満 shouman (~May 21)
    {"kanji": "蚕起食桑",   "reading": "かいこおきてくわをはむ",     "gloss": "silkworms wake and eat mulberry",     "sekkiId": "shouman",   "dateRange": {"start": "05-21", "end": "05-25"}, "description": {"ja": "蚕が起き出して桑の葉を盛んに食べ始める。絹の生産が本格化する初夏の農村の光景。"}},
    {"kanji": "紅花栄",     "reading": "べにばなさかう",             "gloss": "safflowers bloom",                    "sekkiId": "shouman",   "dateRange": {"start": "05-26", "end": "05-30"}, "description": {"ja": "紅花が咲き誇る。染料や化粧品に使われる鮮やかな橙紅色の花が畑を彩る。"}},
    {"kanji": "麦秋至",     "reading": "むぎのときいたる",           "gloss": "wheat ripens",                        "sekkiId": "shouman",   "dateRange": {"start": "05-31", "end": "06-05"}, "description": {"ja": "麦が黄金色に実り、刈り入れの時を迎える。初夏の穀物の収穫期が訪れる。"}},
    # 芒種 boshu (~Jun 6)
    {"kanji": "螳螂生",     "reading": "かまきりしょうず",           "gloss": "praying mantises hatch",              "sekkiId": "boshu",     "dateRange": {"start": "06-06", "end": "06-10"}, "description": {"ja": "カマキリが卵から孵化する。草むらで小さな命が一斉に動き始める初夏の情景。"}},
    # NOTE: the canonical first Kō of boshu is 腐草為螢 (rotten grass becomes fireflies),
    # which is actually the SECOND Kō. The entry below preserves existing slice #9 data verbatim.
    {"kanji": "腐草為螢",   "reading": "くされたるくさほたるとなる", "gloss": "rotten grass becomes fireflies",       "sekkiId": "boshu",     "dateRange": {"start": "06-11", "end": "06-15"}, "description": {"ja": "腐った草からホタルが生まれると古人は信じた。田や川沿いに蛍の光が揺れ始める頃。"}},
    {"kanji": "梅子黄",     "reading": "うめのみきばむ",             "gloss": "plums turn yellow",                   "sekkiId": "boshu",     "dateRange": {"start": "06-16", "end": "06-20"}, "description": {"ja": "梅の実が黄色く熟し始める。梅雨の雨を吸って膨らんだ実が梅酒や梅干しの材料となる。"}},
    # 夏至 geshi (~Jun 21)
    {"kanji": "乃東枯",     "reading": "なつかれくさかるる",         "gloss": "self-heal withers",                   "sekkiId": "geshi",     "dateRange": {"start": "06-21", "end": "06-26"}, "description": {"ja": "夏枯草（カコソウ）が枯れる。夏至の頃に枯れ始めるこの草が、季節の転換点を示す。"}},
    {"kanji": "菖蒲華",     "reading": "あやめはなさく",             "gloss": "irises bloom",                        "sekkiId": "geshi",     "dateRange": {"start": "06-27", "end": "07-01"}, "description": {"ja": "アヤメの花が咲く。紫や白の優雅な花が水辺を彩り、初夏の風情を添える。"}},
    {"kanji": "半夏生",     "reading": "はんげしょうず",             "gloss": "crow-dipper sprouts",                 "sekkiId": "geshi",     "dateRange": {"start": "07-02", "end": "07-06"}, "description": {"ja": "半夏（カラスビシャク）が芽を出す。この時期に農作業の一区切りをつける農家の節目。"}},
    # 小暑 shousho (~Jul 7)
    {"kanji": "温風至",     "reading": "あつかぜいたる",             "gloss": "warm winds arrive",                   "sekkiId": "shousho",   "dateRange": {"start": "07-07", "end": "07-11"}, "description": {"ja": "温かな南風が吹き始める。梅雨が明け、夏本番の蒸し暑い風が列島を包む頃。"}},
    {"kanji": "蓮始開",     "reading": "はすはじめてひらく",         "gloss": "lotus flowers begin to open",         "sekkiId": "shousho",   "dateRange": {"start": "07-12", "end": "07-16"}, "description": {"ja": "蓮の花が開き始める。早朝に池面に開く清らかな花は、夏の朝の風物詩。"}},
    {"kanji": "鷹乃学習",   "reading": "たかすなわちわざをならう",   "gloss": "hawks learn to fly",                  "sekkiId": "shousho",   "dateRange": {"start": "07-17", "end": "07-22"}, "description": {"ja": "ひなの鷹が飛ぶ技を学ぶ。巣立ちの頃、若い鷹が大空へ羽ばたく練習を始める。"}},
    # 大暑 taisho (~Jul 23)
    {"kanji": "桐始結花",   "reading": "きりはじめてはなをむすぶ",   "gloss": "paulownia trees begin to fruit",      "sekkiId": "taisho",    "dateRange": {"start": "07-23", "end": "07-27"}, "description": {"ja": "桐の木が実をつけ始める。夏の盛りに桐の花が実となり、秋への準備が始まる。"}},
    {"kanji": "土潤溽暑",   "reading": "つちうるおうてむしあつし",   "gloss": "earth is damp and sweltering",        "sekkiId": "taisho",    "dateRange": {"start": "07-28", "end": "08-01"}, "description": {"ja": "大地が湿り気を帯び、蒸し暑さが極まる。夏の熱気と湿気が体に重くのしかかる頃。"}},
    {"kanji": "大雨時行",   "reading": "たいうときどきふる",         "gloss": "heavy rains fall at times",           "sekkiId": "taisho",    "dateRange": {"start": "08-02", "end": "08-06"}, "description": {"ja": "時おり激しい夕立が降る。夏の積乱雲が発達し、局地的な大雨をもたらす季節。"}},
    # 立秋 risshu (~Aug 7)
    {"kanji": "涼風至",     "reading": "すずかぜいたる",             "gloss": "cool winds arrive",                   "sekkiId": "risshu",    "dateRange": {"start": "08-07", "end": "08-11"}, "description": {"ja": "涼しい風が吹き始める。暦の上では秋が始まり、夕暮れの風にかすかな秋の気配が漂う。"}},
    {"kanji": "寒蝉鳴",     "reading": "ひぐらしなく",               "gloss": "evening cicadas begin to sing",       "sekkiId": "risshu",    "dateRange": {"start": "08-12", "end": "08-16"}, "description": {"ja": "ヒグラシが夕暮れに鳴き始める。カナカナという哀愁ある声が秋の気配を告げる。"}},
    {"kanji": "蒙霧升降",   "reading": "ふかきりまとう",             "gloss": "thick mist rises and falls",          "sekkiId": "risshu",    "dateRange": {"start": "08-17", "end": "08-22"}, "description": {"ja": "深い霧が立ちこめる。朝夕の気温差が大きくなり、霧が山や川を包む晩夏の情景。"}},
    # 処暑 shosho (~Aug 23)
    {"kanji": "綿柎開",     "reading": "わたのはなしべひらく",       "gloss": "cotton bolls open",                   "sekkiId": "shosho",    "dateRange": {"start": "08-23", "end": "08-27"}, "description": {"ja": "綿の実が弾けて白い綿毛を覗かせる。暑さが和らぎ、秋の収穫が近づく頃。"}},
    {"kanji": "天地始粛",   "reading": "てんちはじめてさむし",       "gloss": "heaven and earth begin to cool",      "sekkiId": "shosho",    "dateRange": {"start": "08-28", "end": "09-01"}, "description": {"ja": "天地が冷えひきしまり始める。万物が静まり、秋の厳しさへと向かう転換の時期。"}},
    {"kanji": "禾乃登",     "reading": "こくものすなわちみのる",     "gloss": "grain ripens on the stalk",           "sekkiId": "shosho",    "dateRange": {"start": "09-02", "end": "09-07"}, "description": {"ja": "稲穂が実り始める。黄金色に染まる田んぼが、秋の収穫の喜びを予感させる。"}},
    # 白露 hakuro (~Sep 8)
    {"kanji": "草露白",     "reading": "くさのつゆしろし",           "gloss": "white dew appears on grass",          "sekkiId": "hakuro",    "dateRange": {"start": "09-08", "end": "09-12"}, "description": {"ja": "草の葉に白い露が宿る。朝の冷気が強まり、露が光を集めて輝く秋の情景。"}},
    {"kanji": "鶺鴒鳴",     "reading": "せきれいなく",               "gloss": "wagtails begin to sing",              "sekkiId": "hakuro",    "dateRange": {"start": "09-13", "end": "09-17"}, "description": {"ja": "セキレイが鳴き始める。川岸で尾を上下に動かしながら鳴く姿が秋の水辺の風物詩。"}},
    {"kanji": "玄鳥去",     "reading": "つばめさる",                 "gloss": "swallows depart",                     "sekkiId": "hakuro",    "dateRange": {"start": "09-18", "end": "09-22"}, "description": {"ja": "ツバメが南へ旅立つ。春に渡ってきたツバメが越冬のため南の地へと去っていく別れの季節。"}},
    # 秋分 shubun (~Sep 23)
    {"kanji": "雷乃収声",   "reading": "かみなりすなわちこえをおさむ","gloss": "thunder ceases",                     "sekkiId": "shubun",    "dateRange": {"start": "09-23", "end": "09-27"}, "description": {"ja": "雷が鳴らなくなる。夏の間活発だった雷が静まり、秋の穏やかな空が広がり始める。"}},
    {"kanji": "蟄虫坏戸",   "reading": "むしかくれてとをふさぐ",     "gloss": "insects seal their doors",            "sekkiId": "shubun",    "dateRange": {"start": "09-28", "end": "10-02"}, "description": {"ja": "虫たちが土の中に閉じこもり始める。冬支度の始まりを告げる秋の深まりの頃。"}},
    {"kanji": "水始涸",     "reading": "みずはじめてかるる",         "gloss": "waters begin to dry",                 "sekkiId": "shubun",    "dateRange": {"start": "10-03", "end": "10-07"}, "description": {"ja": "田の水が干され始める。稲刈りを終えた田んぼが乾き、農の一年が締めくくられる。"}},
    # 寒露 kanro (~Oct 8)
    {"kanji": "鴻雁来",     "reading": "こうがんきたる",             "gloss": "wild geese arrive",                   "sekkiId": "kanro",     "dateRange": {"start": "10-08", "end": "10-12"}, "description": {"ja": "雁が北から渡ってくる。冬を日本で過ごすために南下してくる渡り鳥の到着を告げる。"}},
    {"kanji": "菊花開",     "reading": "きくのはなひらく",           "gloss": "chrysanthemums bloom",                "sekkiId": "kanro",     "dateRange": {"start": "10-13", "end": "10-17"}, "description": {"ja": "菊の花が咲き始める。秋の花の王者として庭や野山に彩りを添える季節。"}},
    {"kanji": "蟋蟀在戸",   "reading": "きりぎりすとにあり",         "gloss": "crickets chirp at the door",          "sekkiId": "kanro",     "dateRange": {"start": "10-18", "end": "10-22"}, "description": {"ja": "コオロギが戸口で鳴く。秋の夜長に虫の音が響き、静けさの中に命の気配を感じる頃。"}},
    # 霜降 soko (~Oct 23)
    {"kanji": "霜始降",     "reading": "しもはじめてふる",           "gloss": "frost begins to fall",                "sekkiId": "soko",      "dateRange": {"start": "10-23", "end": "10-27"}, "description": {"ja": "初霜が降りる。夜の冷え込みが強まり、朝の地面が白く輝く晩秋の到来を告げる。"}},
    {"kanji": "霎時施",     "reading": "こさめときどきふる",         "gloss": "light rains fall intermittently",     "sekkiId": "soko",      "dateRange": {"start": "10-28", "end": "11-01"}, "description": {"ja": "小雨が時おり降る。晩秋の冷たい雨が木の葉を落とし、冬への移ろいを促す。"}},
    {"kanji": "楓蔦黄",     "reading": "もみじつたきばむ",           "gloss": "maples and ivies turn yellow",        "sekkiId": "soko",      "dateRange": {"start": "11-02", "end": "11-06"}, "description": {"ja": "紅葉やツタが黄色く染まる。山や庭が錦に彩られ、秋の深まりを色鮮やかに告げる。"}},
    # 立冬 rittou (~Nov 7)
    {"kanji": "山茶始開",   "reading": "つばきはじめてひらく",       "gloss": "camellias begin to bloom",            "sekkiId": "rittou",    "dateRange": {"start": "11-07", "end": "11-11"}, "description": {"ja": "山茶花（サザンカ）が咲き始める。冬枯れの中で白や赤の花が清楚に咲く初冬の花。"}},
    {"kanji": "地始凍",     "reading": "ちはじめてこおる",           "gloss": "ground begins to freeze",             "sekkiId": "rittou",    "dateRange": {"start": "11-12", "end": "11-16"}, "description": {"ja": "大地が凍り始める。朝の冷え込みで地面が固く締まり、冬の到来を体で感じる頃。"}},
    {"kanji": "金盞香",     "reading": "きんせんかさく",             "gloss": "narcissus blooms and scents the air", "sekkiId": "rittou",    "dateRange": {"start": "11-17", "end": "11-21"}, "description": {"ja": "水仙が咲き始め、甘い香りを漂わせる。冬の訪れとともに清らかな花が野や庭に咲く。"}},
    # 小雪 shousetsu (~Nov 22)
    {"kanji": "虹蔵不見",   "reading": "にじかくれてみえず",         "gloss": "rainbows hide and are unseen",        "sekkiId": "shousetsu", "dateRange": {"start": "11-22", "end": "11-26"}, "description": {"ja": "虹が見えなくなる。冬の曇り空が広がり、鮮やかな虹の季節が終わりを告げる。"}},
    {"kanji": "朔風払葉",   "reading": "きたかぜこのはをはらう",     "gloss": "north wind sweeps the leaves",        "sekkiId": "shousetsu", "dateRange": {"start": "11-27", "end": "12-01"}, "description": {"ja": "北風が木の葉を吹き払う。冷たい季節風が残り葉を落とし、木々が冬の骨格を見せる。"}},
    {"kanji": "橘始黄",     "reading": "たちばなはじめてきばむ",     "gloss": "tachibana citrus begins to yellow",   "sekkiId": "shousetsu", "dateRange": {"start": "12-02", "end": "12-06"}, "description": {"ja": "橘の実が黄色く色づき始める。常緑の葉の中に黄金色の実が輝く冬の風物詩。"}},
    # 大雪 taisetsu (~Dec 7)
    {"kanji": "閉塞成冬",   "reading": "そらさむくふゆとなる",       "gloss": "skies close and winter settles",      "sekkiId": "taisetsu",  "dateRange": {"start": "12-07", "end": "12-11"}, "description": {"ja": "空が閉じて冬が訪れる。厚い雲が空を覆い、天地の気が塞がれて本格的な冬となる。"}},
    {"kanji": "熊蟄穴",     "reading": "くまあなにこもる",           "gloss": "bears retreat into their dens",       "sekkiId": "taisetsu",  "dateRange": {"start": "12-12", "end": "12-16"}, "description": {"ja": "熊が穴に入って冬ごもりをする。雪深い山中で大きな命が静かに眠りにつく頃。"}},
    {"kanji": "鱖魚群",     "reading": "さけのうおむらがる",         "gloss": "salmon gather and swim upstream",     "sekkiId": "taisetsu",  "dateRange": {"start": "12-17", "end": "12-21"}, "description": {"ja": "鮭が群れをなして川を遡上する。生まれた川へ戻る鮭の力強い姿が冬の川を彩る。"}},
    # 冬至 touji (~Dec 22)
    {"kanji": "乃東生",     "reading": "なつかれくさしょうず",       "gloss": "self-heal sprouts anew",              "sekkiId": "touji",     "dateRange": {"start": "12-22", "end": "12-26"}, "description": {"ja": "夏枯草が芽吹く。冬至の頃に新たな芽を出すこの草は、陽の復活の象徴とされる。"}},
    {"kanji": "麋角解",     "reading": "おおしかのつのおつる",       "gloss": "elk shed their antlers",              "sekkiId": "touji",     "dateRange": {"start": "12-27", "end": "12-31"}, "description": {"ja": "大鹿が角を落とす。一年の終わりに角を脱ぎ、新たな命の周期が始まる静かな時節。"}},
    {"kanji": "雪下出麦",   "reading": "ゆきわたりてむぎいずる",     "gloss": "wheat sprouts beneath the snow",      "sekkiId": "touji",     "dateRange": {"start": "01-01", "end": "01-04"}, "description": {"ja": "雪の下から麦が芽を出す。寒さの中でも麦は静かに育ち、春の収穫を夢見て根を張る。"}},
    # 小寒 shoukan (~Jan 6)
    {"kanji": "芹乃栄",     "reading": "せりすなわちさかう",         "gloss": "Japanese parsley flourishes",         "sekkiId": "shoukan",   "dateRange": {"start": "01-05", "end": "01-09"}, "description": {"ja": "芹が青々と茂り始める。冷たい水辺で新鮮な緑を宿す芹が七草のひとつとして摘まれる。"}},
    {"kanji": "水泉動",     "reading": "しみずあたたかをふくむ",     "gloss": "springs begin to move under ice",     "sekkiId": "shoukan",   "dateRange": {"start": "01-10", "end": "01-14"}, "description": {"ja": "凍った地下の泉が動き始める。最も寒い時期でも地中では水が温もりを蓄えて流れ出す。"}},
    {"kanji": "雉始雊",     "reading": "きじはじめてなく",           "gloss": "pheasants begin to call",             "sekkiId": "shoukan",   "dateRange": {"start": "01-15", "end": "01-19"}, "description": {"ja": "雉が鳴き始める。冬の野に雄の雉が高らかに声を上げ、繁殖の季節が近づく予兆。"}},
    # 大寒 daikan (~Jan 20)
    {"kanji": "款冬華",     "reading": "ふきのはなさく",             "gloss": "butterbur flowers bloom",             "sekkiId": "daikan",    "dateRange": {"start": "01-20", "end": "01-24"}, "description": {"ja": "フキノトウが花を咲かせる。極寒の大地を割って顔を出す春の使者として親しまれる。"}},
    {"kanji": "水沢腹堅",   "reading": "さわみずこおりつめる",       "gloss": "ice thickens on streams",             "sekkiId": "daikan",    "dateRange": {"start": "01-25", "end": "01-29"}, "description": {"ja": "沢の水が厚く凍り付く。一年で最も寒さが厳しく、氷が地の底まで張り詰める頃。"}},
    {"kanji": "鶏始乳",     "reading": "にわとりはじめてとやにつく", "gloss": "hens begin to lay",                   "sekkiId": "daikan",    "dateRange": {"start": "01-30", "end": "02-03"}, "description": {"ja": "鶏が卵を産み始める。厳寒の中でも春の近づきを感じ、命が動き出す冬の終わりの証。"}},
]


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


def build_sekki() -> list[dict]:
    """Return the canonical 24 Sekki list, validated for required localized fields (ADR 0014)."""
    assert len(SEKKI_DATA) == 24, f"Expected 24 Sekki, got {len(SEKKI_DATA)}"
    for s in SEKKI_DATA:
        assert s.get("gloss", {}).get("ja"), (
            f"Sekki '{s['id']}' is missing a non-empty gloss.ja (ADR 0014 requires it)"
        )
        assert s.get("description", {}).get("ja"), (
            f"Sekki '{s['id']}' is missing a non-empty description.ja (ADR 0014 requires it)"
        )
    return SEKKI_DATA


def build_ko() -> list[dict]:
    """Return the canonical 72 Kō list, validated for completeness and tiling."""
    assert len(KO_DATA) == 72, f"Expected 72 Kō, got {len(KO_DATA)}"
    sekki_ids = {s["id"] for s in SEKKI_DATA}
    for ko in KO_DATA:
        assert ko["sekkiId"] in sekki_ids, f"Kō '{ko['kanji']}' has unknown sekkiId '{ko['sekkiId']}'"
        assert ko["kanji"], f"Kō has empty kanji"
        assert ko["reading"], f"Kō '{ko['kanji']}' has empty reading"
        assert ko["gloss"], f"Kō '{ko['kanji']}' has empty gloss"
        assert ko.get("description", {}).get("ja"), (
            f"Kō '{ko['kanji']}' is missing a non-empty description.ja (ADR 0014 requires it)"
        )

    # --- Tiling validation: all 366 days must be covered exactly once (no gaps, no overlaps) ---
    # Build ordered day list for a leap year (366 days: 01-01..12-31 including 02-29)
    days_in_month = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    all_days: list[str] = []
    for month in range(1, 13):
        for day in range(1, days_in_month[month - 1] + 1):
            all_days.append(f"{month:02d}-{day:02d}")
    day_index = {d: i for i, d in enumerate(all_days)}

    coverage = [0] * 366
    for ko in KO_DATA:
        start, end = ko["dateRange"]["start"], ko["dateRange"]["end"]
        si, ei = day_index[start], day_index[end]
        assert si <= ei, (
            f"Kō '{ko['kanji']}' has start {start} after end {end} — "
            f"cross-year spans are not supported in this model"
        )
        for i in range(si, ei + 1):
            coverage[i] += 1

    gaps = [all_days[i] for i, c in enumerate(coverage) if c == 0]
    overlaps = [all_days[i] for i, c in enumerate(coverage) if c > 1]
    assert not gaps, f"Kō ranges leave uncovered days: {gaps}"
    assert not overlaps, f"Kō ranges overlap on days: {overlaps}"

    return KO_DATA


def main() -> None:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    manifest_path = os.path.join(repo_root, "Resources", "manifest.json")

    daily_map = build_daily_map()
    sekki = build_sekki()
    ko = build_ko()

    # Validate counts before writing
    assert len(daily_map) == 366, f"Expected 366 entries, got {len(daily_map)}"
    assert "02-29" in daily_map, "Missing 02-29 leap day"
    assert len(sekki) == 24, f"Expected 24 Sekki, got {len(sekki)}"
    assert len(ko) == 72, f"Expected 72 Kō, got {len(ko)}"

    manifest = {
        "schemaVersion": "1.2",
        "dailyMap": dict(sorted(daily_map.items())),  # stable sort by MM-DD
        "ko": ko,
        "sekki": sekki,
    }

    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")  # POSIX trailing newline

    print(f"Wrote {len(daily_map)} daily map entries, {len(ko)} Kō, {len(sekki)} Sekki to {manifest_path}")


if __name__ == "__main__":
    main()
