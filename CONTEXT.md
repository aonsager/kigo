# Kigo

A calm iOS wellness app that surfaces one seasonal word (**Kigo**) per day, paired with the current Japanese **Microseason**, over a large evocative image. This file fixes the vocabulary so criteria and code stay precise.

## Language

**Kigo** (季語):
A traditional Japanese seasonal word. The app shows exactly one per calendar day.
_Avoid_: keyword, season word, term.

**Daily Map**:
The mapping from a date key to the Kigo shown that day. Now keyed by **absolute `YYYY-MM-DD`** and populated as an instrumented dummy dataset for **every day of 2026** (365 keys, no `02-29`); each entry's description carries its own ISO date so the correct per-day record is verifiably read (ADR 0016, reversing the earlier perennial `MM-DD` keying). A date with no entry (e.g. any 2027 date, before a remote update ships new data) resolves to the defined **content-unavailable** state. The 72 Kō / 24 Sekki remain **perennial** (`MM-DD` ranges).
_Avoid_: schedule, calendar, playlist; "perennial" (the Daily Map no longer is — only Kō/Sekki are).

**Microseason** / **Kō** (候, 七十二候):
One of the 72 micro-seasons of the traditional Japanese almanac, each spanning ~5 days, with a kanji name, reading, and short gloss (e.g. 腐草為螢 "rotten grass becomes fireflies"). The app's secondary display; the Kō is shown primary.
_Avoid_: season (too coarse), period.

**Sekki** (節気, 二十四節気):
One of the 24 solar terms, each spanning ~15 days. Each Kō belongs to exactly one Sekki. Shown as secondary context beneath the Kō.
_Avoid_: solar season.

**Today**:
The current calendar day in the **device's local time zone**. Drives both the Kigo (via the Daily Map) and the current Kō/Sekki.

**ContentSource**:
The protocol the app loads content through. `BundledContentSource` reads the generated, bundled manifest (the seed/fallback; dev + tests). The **RemoteManifestSource** seam (ADR 0017) fetches a newer versioned manifest over the network. The seam that lets content move to a real API without touching the UI.

**RemoteManifestSource** / **remote update**:
The injectable seam (`fetchLatest() async throws -> Manifest`) that reads a **versioned** manifest from a placeholder remote `https` URL. On app open the store serves local content immediately and checks the remote in the background, replacing the local copy **iff** the remote `version` is strictly newer and the body decodes/validates; any failure silently keeps the local copy (ADR 0017). Production is a thin `URLSession` adapter; tests inject an in-memory fake (no live network on the gating path). The real end-to-end fetch is J7.
_Avoid_: "sync" (no two-way state; content is pull-only), "backend" (no server is built — only the client consumes a URL).

**Contract**:
The frozen shape of the served content — a `manifest.json` (Daily Map + 72 Kō + 24 Sekki) plus per-Kigo image slots. Fixed now; the network endpoint that serves it is out of scope.

**Manifest**:
The single content document conforming to the Contract: the full Daily Map, the 72 Kō, and the 24 Sekki, with a `schemaVersion` (shape) and a monotonic integer **`version`** (content freshness, used by the remote-update comparison — ADR 0016/0017).

**Entitlement**:
A user's active "widget access" subscription state, derived from StoreKit and shared with the widget. Active ⇒ the widget reveals the image.

**Widget Gate**:
The rule that the home-screen **Widget** renders the full image+Kigo only when the **Entitlement** is active; without it, the widget shows the Kigo name (kanji + reading) **without the image**.

**Premium** / **Basic**:
A user's plan, derived from the **Entitlement**. **Premium** = the Entitlement is
active (the user holds the widget-access subscription). **Basic** = no active
Entitlement (the free default). These are display words for the two entitlement
states; there is no separate account or stored "plan" — plan ⇔ Entitlement state.
_Avoid_: "free tier" / "paid tier" (implies multiple products; there is one), "pro".

**Paywall**:
The single screen offering the auto-renewable "widget access" subscription. Reached
from the Today screen via the **Upgrade entry**, presented as a sheet. For a **Basic**
user it shows the premium **Benefits**, the price and subscription duration, a
prominent buy button, a Restore Purchases button, and links to Terms of Use and a
Privacy Policy (all required by App Store review of auto-renewable subscriptions).
For a **Premium** user it shows an active/manage state instead of the buy button.

**Upgrade entry**:
The small, low-contrast control in a corner of the Today screen that opens the
**Paywall**. Deliberately unobtrusive so it does not disturb the calm nightstand
aesthetic (J1); the prominence lives inside the Paywall splash, not on the Today
screen. Shown in both plan states (opens the buy offer for **Basic**, the manage
state for **Premium**).
_Avoid_: "upgrade banner", "buy button" (that is the prominent control *inside* the Paywall).

**Benefits**:
The premium value proposition shown on the **Paywall**. The subscription unlocks
exactly one capability — the **Widget Gate** revealing the day's image on the home
screen — so the Benefits are an honest single benefit (with supporting sub-points),
never invented features.

**SubscriptionPurchaser**:
The injectable StoreKit seam that *initiates* a purchase of the widget-access product
(production: StoreKit 2 `Product.purchase()`; tests: an in-memory fake returning a
configured outcome). Mirrors `EntitlementTransactionSource` (which *reads* held
entitlements) — splitting "start a purchase" from "read what is owned" so the
purchase→activation *logic* is verifiable headlessly without a real purchase sheet
(which hangs under `xcodebuild` from the CLI — ADR 0009).

**Offer display** (ProductInfo seam):
The injectable seam supplying the **Paywall**'s display price and subscription
duration (production: a StoreKit 2 `Product`; tests: a fake). Loading a real
`Product` from the App Store, like a real purchase, is off the headless gating path;
the seam lets the price/duration *rendering* be tested deterministically.

**Asagiri** (朝霧, "morning mist"):
The visual direction of the revamp: full-bleed per-day photography, centered sumi-ink
**Mincho** typography (Shippori Mincho for the Kigo kanji/titles, Zen Kaku Gothic New
for readings/UI), generous quiet space, and a feathered frosted-glass legibility plate
behind the centered text. Rendered in both **light and dark Appearance**. The named
target look the revamp is judged against (J6); pixel-fidelity is never a termination gate.

**Appearance**:
Light or dark. In production the app follows the **system** appearance. Under UI test it
is pinned deterministically via the `KIGO_FAKE_APPEARANCE=light|dark` launch-environment
variable (mirroring `KIGO_FAKE_DATE`, ADR 0013).

**Microseason Almanac** (or just **Almanac**):
The opt-in depth layer for the Microseason on the Today screen. Its **resting state** is a
one-line `Sekki` kanji (left, no reading) · `Kō` kanji+reading (right) above a **Year
timeline**; tapping it expands a bottom sheet (same motion as the Paywall) showing, for
both Kō and Sekki: the year-position counter, a **progress gauge**, the gloss, and a prose
description. Replaces the old floating Microseason line. Preserves the "only today" calm —
the learning layer is opt-in.
_Avoid_: "calendar", "history" (it shows only today's position, never other days).

**Year timeline**:
72 thin ticks (one per Kō) spanning the screen width, today's Kō lit in the accent colour,
over four faint season-tint bands (春夏秋冬). The resting "you are here in the year" strip
under the Microseason line.

**Almanac positions** (derived, not stored):
The four positions the Almanac renders, all derived by the resolver from the bundled
Manifest for today's date:
- **Kō year-position** — N of 72, **1-indexed** (梅子黄 is 27/72; the lit tick).
- **Sekki year-position** — M of 24, 1-indexed.
- **Day-within-Kō** — d of the Kō's date-range length (~5 days), 1-indexed → the day gauge.
- **Kō-within-Sekki** — k of the ~3 Kō sharing that Sekki, 1-indexed → the sekki gauge.
_Indexing is 1-indexed everywhere_ (resolved ambiguity; the mockup's "26/72" was 0-indexed).

**Image Attribution** / **Attribution panel**:
Per-image credit metadata (title, 写真/photographer credit, license/source) carried in the
Manifest alongside each image. Surfaced by the **(i)** control in the Today screen's
top-left, which slides a panel down from the top edge (dismissed by its grab indicator or a
backdrop tap — no label, no close button). Values are **placeholders** while images are
placeholders (J2/J6); the fields' presence and well-formedness are gated (C12, C14).

**Settings menu**:
The sheet opened by the **Settings gear** (top-right of the Today screen) — the revamp's
replacement for the bare **Upgrade entry**. Houses three sections: (1) the **Language
preference** switcher, (2) the widget **Benefits** + price + buy/manage (the Paywall offer,
unchanged in substance — one product, one honest benefit), and (3) the Terms/Privacy legal
links. Reuses the existing `paywall.*` accessibility identifiers (`paywall.entry` on the
gear, `paywall.sheet` on the menu), so the Paywall criteria (C9/C10) still hold.
_Avoid_: "settings screen" (it is a sheet, not a separate destination); "store".

**Language preference**:
The user's chosen language, **Japanese** (default) or **English**, selected in the **Settings
menu** and persisted. Drives **both** the app's UI-chrome strings **and** the localized
**content** — every Kigo/Kō/Sekki description and gloss, the attribution, and the **readings**
(`ja`=hiragana, `en`=romaji) — now populated in both languages (ADR 0018). The Kigo/Kō/Sekki
**kanji names are content and never translate** (shown identically in both languages). The
preference is exposed as a single **observable language store**, so changing it re-renders every
visible string **live, without relaunch** (C20). Under UI test the *initial* value is pinnable via
`KIGO_FAKE_LANGUAGE=ja|en`; the live toggle is driven through the Settings switcher.
_Avoid_: "locale" (no region/number/date *formatting* is in scope — only language strings switch).

## Relationships

- A **Daily Map** entry references one **Kigo**; **Today** selects the entry by absolute `YYYY-MM-DD` (2026 dataset); an out-of-range date yields the content-unavailable state.
- **Today** also resolves to exactly one **Kō**, which belongs to exactly one **Sekki**.
- The app reads all content through a **ContentSource**; the **BundledContentSource** is fed the generated **Manifest**.
- An active **Entitlement** unlocks the image in the **Widget**; otherwise the **Widget Gate** hides it.
- A user is **Premium** ⇔ their **Entitlement** is active, else **Basic**; this drives what the **Paywall** shows.
- The **Settings gear** (top-right, the revamp's replacement for the bare **Upgrade entry**) opens the **Settings menu**, whose widget section is the **Paywall** offer; the buy button drives the **SubscriptionPurchaser**, whose success refreshes the **Entitlement** (activating the **Widget Gate**).
- **Today** also resolves the four **Almanac positions** (Kō N/72, Sekki M/24, Day-within-Kō, Kō-within-Sekki) rendered by the **Microseason Almanac**.
- Each **Daily Map** image carries **Image Attribution** surfaced by the **(i)** Attribution panel.
- The **Language preference** switches **UI-chrome** strings **and localized content** (descriptions, glosses, attribution, romanized readings) **live**; **content kanji names never translate**.
- The app serves the bundled/cached **Manifest** immediately on open and updates it in the background from the **RemoteManifestSource** when a strictly newer `version` is available.

## Example dialogue

> **Dev:** "On June 12, 2026, what does the widget show for someone who never subscribed?"
> **Domain expert:** "The **Kigo** name for `2026-06-12` from the **Daily Map** — kanji and reading — but no image. The image is the gated part. And the **Kō** is whichever of the 72 perennial micro-seasons covers June 12, shown above its parent **Sekki**."

## Flagged ambiguities

- "Season" was used loosely — resolved into **Kō** (72, ~5 days, primary) vs **Sekki** (24, ~15 days, secondary). Neither means the four coarse seasons.
- "Gate the widget" first read as hiding the whole widget — resolved: the widget always renders; only the **image** is gated, non-subscribers still see the Kigo name.
- The Microseason **Almanac positions** are **1-indexed** everywhere (梅子黄 = 27/72). The Asagiri mockup showed "26/72" (0-indexed); resolved to 1-indexed to match the lit tick and natural reading.
- "Language switcher" scope evolved: first deferred to **UI-chrome** strings only (ADR 0014), now expanded to **full JP/EN content localization** — descriptions, glosses, attribution, and **romanized readings** — switching **live** without relaunch (ADR 0018). Content **kanji names still never translate**, and **no region/number/date locale formatting** is in scope.
- "Perennial Daily Map" reversed: the Daily Map is now keyed by **absolute 2026 dates** (instrumented dummy data, date-stamped per entry) per ADR 0016; only the **Kō/Sekki** stay perennial. Out-of-range dates show the content-unavailable state.
