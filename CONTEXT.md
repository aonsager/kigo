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
A user's active subscription state, derived from StoreKit. Active ⇒ the in-app **understanding
layer** is revealed (ADR 0019). The product id retains the legacy name
`com.tomeitotameigo.kigo.widgets.monthly` (the `.widgets.` segment predates the inversion).
_Avoid_: "widget access" (the subscription no longer gates the widget — the widget is free).

**Encounter / Understanding** (the free/paid line — ADR 0019):
The product's monetization split. The **Encounter** (free, for everyone) is the day's beauty —
the full-bleed image, the Kigo **kanji** + **reading** — in the app, on the ungated **Widget**,
and via the opt-in **Daily reminder**. The **Understanding** (paid, gated by the **Entitlement**)
is the Kigo's full **description**/significance prose, the **Microseason** (Kō/Sekki) display, and
the **Almanac** depth. "Understanding layer" names the gated bundle collectively.

**Meaning Gate** (replaces the retired **Widget Gate** — ADR 0019):
The rule that the in-app **Understanding** layer renders only when the **Entitlement** is active.
For a **Basic** user the Today screen shows the **Meaning entry** in place of the description and
microseason; for a **Premium** user it shows the full understanding layer.
_Avoid_: "Widget Gate" (retired — the widget is no longer gated).

**Widget** (ungated — ADR 0019):
The home-screen widget. It always renders today's image + Kigo kanji + reading for **everyone**,
regardless of **Entitlement** — it is part of the free **Encounter** and exists to reduce friction
to the daily glimpse, not as a paid perk. It no longer reads the entitlement (the app group /
shared store is no longer required by it).

**Meaning entry**:
The single quiet, tappable line a **Basic** user sees on the Today screen where the description
would sit (e.g. *"what does 蛍 mean? →"*, accessibility id `meaning.upsell`). It opens the
**Paywall**. The only on-screen upsell — calm, never a lock badge on the image (J5).

**Daily reminder**:
An opt-in daily **local** notification at **08:00** local carrying today's Kigo (kanji + reading)
and a gentle curiosity hook. Enabled via a default-**off** toggle (`settings.dailyReminder`) in the
**Settings menu**; enabling it requests notification permission at that moment. **Free for all**,
one per day. Its scheduling logic sits behind an injectable `NotificationScheduler` seam (ADR 0009
pattern); the real delivery is off the gating path (J9).
_Avoid_: "push" (it is a local notification, not APNs), "alarm".

**Premium** / **Basic**:
A user's plan, derived from the **Entitlement**. **Premium** = the Entitlement is
active (the user holds the understanding subscription — they see the **Understanding** layer).
**Basic** = no active Entitlement (the free default — the **Encounter** only, with the **Meaning
entry** in place of the understanding layer). These are display words for the two entitlement
states; there is no separate account or stored "plan" — plan ⇔ Entitlement state.
_Avoid_: "free tier" / "paid tier" (implies multiple products; there is one), "pro".

**Paywall**:
The single screen offering the auto-renewable subscription (unlocking the **Understanding**
layer — ADR 0019). Reached from the Today screen via **two** entries that open the same sheet:
the **Settings gear** (`paywall.entry`) and, for a **Basic** user, the **Meaning entry**
(`meaning.upsell`). For a **Basic** user it shows the premium **Benefits**, the price and
subscription duration, a prominent buy button, a Restore Purchases button, and links to Terms of
Use and a Privacy Policy (all required by App Store review of auto-renewable subscriptions).
For a **Premium** user it shows an active/manage state instead of the buy button.

**Upgrade entry** (legacy umbrella; superseded by the **Settings gear** + **Meaning entry**):
The original small, low-contrast Today-screen control that opened the **Paywall**. The Asagiri
revamp replaced it with the top-right **Settings gear**, and ADR 0019 added a second entry, the
**Meaning entry** (`meaning.upsell`), for **Basic** users. Both stay deliberately unobtrusive so
they do not disturb the calm nightstand aesthetic (J1/J5); the prominence lives inside the Paywall
splash, not on the Today screen. The `paywall.entry` accessibility id now lives on the Settings
gear.
_Avoid_: "upgrade banner", "buy button" (that is the prominent control *inside* the Paywall).

**Benefits**:
The premium value proposition shown on the **Paywall**. The subscription unlocks the
**Understanding** layer — the Kigo's full description/significance prose, the **Microseason**
display, and the **Almanac** depth (ADR 0019) — so the Benefits honestly describe *understanding
the day*, never the (free) widget and never invented features.
_Avoid_: framing the widget or the daily reminder as a benefit (both are free).

**SubscriptionPurchaser**:
The injectable StoreKit seam that *initiates* a purchase of the subscription product
(`com.tomeitotameigo.kigo.widgets.monthly` — legacy name; production: StoreKit 2
`Product.purchase()`; tests: an in-memory fake returning a
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
replacement for the bare **Upgrade entry**. Houses: (1) the **Language preference** switcher,
(2) an Appearance switcher, (3) the **Benefits** + price + buy/manage (the Paywall offer — now
unlocking the **Understanding** layer, ADR 0019), (4) the default-off **Daily reminder** toggle
(`settings.dailyReminder`), and (5) the Terms/Privacy legal links. Reuses the existing `paywall.*`
accessibility identifiers (`paywall.entry` on the gear, `paywall.sheet` on the menu), so the
Paywall criteria (C9/C10) still hold.
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
- An active **Entitlement** reveals the in-app **Understanding** layer (description + Microseason + Almanac) via the **Meaning Gate**; an inactive one shows the **Meaning entry** in its place. The **Widget** is **ungated** — it shows today's image + Kigo for everyone, independent of the Entitlement (ADR 0019).
- A user is **Premium** ⇔ their **Entitlement** is active, else **Basic**; this drives the **Meaning Gate** and what the **Paywall** shows.
- The **Settings gear** (top-right) and, for a **Basic** user, the **Meaning entry** (`meaning.upsell`) both open the **Paywall**; the buy button drives the **SubscriptionPurchaser**, whose success refreshes the **Entitlement** (revealing the Understanding layer via the **Meaning Gate**).
- The **Daily reminder** (opt-in Settings toggle, default off, 08:00 local, free) schedules one local notification with today's Kigo via the injectable `NotificationScheduler` seam.
- **Today** also resolves the four **Almanac positions** (Kō N/72, Sekki M/24, Day-within-Kō, Kō-within-Sekki) rendered by the **Microseason Almanac**.
- Each **Daily Map** image carries **Image Attribution** surfaced by the **(i)** Attribution panel.
- The **Language preference** switches **UI-chrome** strings **and localized content** (descriptions, glosses, attribution, romanized readings) **live**; **content kanji names never translate**.
- The app serves the bundled/cached **Manifest** immediately on open and updates it in the background from the **RemoteManifestSource** when a strictly newer `version` is available.

## Example dialogue

> **Dev:** "On June 12, 2026, what does someone who never subscribed see?"
> **Domain expert:** "On the **Widget** and in the app's **Encounter**: the image for `2026-06-12` plus the **Kigo** kanji + reading from the **Daily Map** — the widget is free and ungated now. What they *don't* see in the app is the **Understanding** layer — the description, the **Microseason** (Kō/Sekki), and the **Almanac** — in its place the Today screen shows the quiet **Meaning entry** that opens the **Paywall**. The image is no longer the gated part; *understanding* is (ADR 0019)."

## Flagged ambiguities

- "Season" was used loosely — resolved into **Kō** (72, ~5 days, primary) vs **Sekki** (24, ~15 days, secondary). Neither means the four coarse seasons.
- "Gate the widget" first read as hiding the whole widget, then resolved (originally) to gating only the **image** — and has since been **reversed entirely** (ADR 0019): the widget is now **free and ungated** (image + Kigo for everyone), and the paid gate moved *into the app* onto the **Understanding** layer (the **Meaning Gate**). The widget was a poor paywall feature because it is undiscoverable; free, it instead reduces friction to the daily encounter.
- The Microseason **Almanac positions** are **1-indexed** everywhere (梅子黄 = 27/72). The Asagiri mockup showed "26/72" (0-indexed); resolved to 1-indexed to match the lit tick and natural reading.
- "Language switcher" scope evolved: first deferred to **UI-chrome** strings only (ADR 0014), now expanded to **full JP/EN content localization** — descriptions, glosses, attribution, and **romanized readings** — switching **live** without relaunch (ADR 0018). Content **kanji names still never translate**, and **no region/number/date locale formatting** is in scope.
- "Perennial Daily Map" reversed: the Daily Map is now keyed by **absolute 2026 dates** (instrumented dummy data, date-stamped per entry) per ADR 0016; only the **Kō/Sekki** stay perennial. Out-of-range dates show the content-unavailable state.
