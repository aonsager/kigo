# Kigo

A calm iOS wellness app that surfaces one seasonal word (**Kigo**) per day, paired with the current Japanese **Microseason**, over a large evocative image. This file fixes the vocabulary so criteria and code stay precise.

## Language

**Kigo** (季語):
A traditional Japanese seasonal word. The app shows exactly one per calendar day.
_Avoid_: keyword, season word, term.

**Daily Map**:
The perennial mapping from a month-day key (`MM-DD`) to the Kigo shown that day. Keyed by `MM-DD` so the same date shows the same Kigo every year. Covers all 366 keys (includes `02-29`).
_Avoid_: schedule, calendar, playlist.

**Microseason** / **Kō** (候, 七十二候):
One of the 72 micro-seasons of the traditional Japanese almanac, each spanning ~5 days, with a kanji name, reading, and short gloss (e.g. 腐草為螢 "rotten grass becomes fireflies"). The app's secondary display; the Kō is shown primary.
_Avoid_: season (too coarse), period.

**Sekki** (節気, 二十四節気):
One of the 24 solar terms, each spanning ~15 days. Each Kō belongs to exactly one Sekki. Shown as secondary context beneath the Kō.
_Avoid_: solar season.

**Today**:
The current calendar day in the **device's local time zone**. Drives both the Kigo (via the Daily Map) and the current Kō/Sekki.

**ContentSource**:
The protocol the app loads content through. `BundledContentSource` reads generated files (dev + tests); `HTTPContentSource` (production, added later) reads the **Contract** over the network. The seam that lets content move to a real API without touching the UI.

**Contract**:
The frozen shape of the served content — a `manifest.json` (Daily Map + 72 Kō + 24 Sekki) plus per-Kigo image slots. Fixed now; the network endpoint that serves it is out of scope.

**Manifest**:
The single content document conforming to the Contract: the full Daily Map, the 72 Kō, and the 24 Sekki, with a `schemaVersion`.

**Entitlement**:
A user's active "widget access" subscription state, derived from StoreKit and shared with the widget. Active ⇒ the widget reveals the image.

**Widget Gate**:
The rule that the home-screen **Widget** renders the full image+Kigo only when the **Entitlement** is active; without it, the widget shows the Kigo name (kanji + reading) **without the image**.

**Paywall**:
The single screen offering the auto-renewable "widget access" subscription, with restore.

## Relationships

- A **Daily Map** entry references one **Kigo**; **Today** selects the entry by `MM-DD`.
- **Today** also resolves to exactly one **Kō**, which belongs to exactly one **Sekki**.
- The app reads all content through a **ContentSource**; the **BundledContentSource** is fed the generated **Manifest**.
- An active **Entitlement** unlocks the image in the **Widget**; otherwise the **Widget Gate** hides it.

## Example dialogue

> **Dev:** "On June 12, what does the widget show for someone who never subscribed?"
> **Domain expert:** "The **Kigo** name for `06-12` from the **Daily Map** — kanji and reading — but no image. The image is the gated part. And the **Kō** is whichever of the 72 covers June 12, shown above its parent **Sekki**."

## Flagged ambiguities

- "Season" was used loosely — resolved into **Kō** (72, ~5 days, primary) vs **Sekki** (24, ~15 days, secondary). Neither means the four coarse seasons.
- "Gate the widget" first read as hiding the whole widget — resolved: the widget always renders; only the **image** is gated, non-subscribers still see the Kigo name.
