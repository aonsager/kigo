# Kigo

> A calm iOS wellness app that surfaces **one traditional Japanese seasonal word per day** — the *Kigo* — over a large, evocative image, paired with today's Japanese **microseason**.

Kigo is meant to feel like a tasteful object on the nightstand: a single quiet
moment a day, not a productivity tool. There is no calendar, no feed, no
streaks, no history — **only today**. The same word is shown to everyone on a
given date.

This document is the central reference for everything the app presents on
screen: each surface, what it shows, and what it does. It is written as the
hand-off brief for design work, so it describes the *content and behavior* of
each screen rather than its current (placeholder) styling.

---

## Table of contents

- [The experience at a glance](#the-experience-at-a-glance)
- [Core vocabulary](#core-vocabulary)
- [Screens & surfaces](#screens--surfaces)
  - [1. Today screen](#1-today-screen-the-home-experience)
  - [2. Loading placeholder](#2-loading-placeholder)
  - [3. Unavailable placeholder](#3-unavailable-placeholder)
  - [4. Upgrade entry](#4-upgrade-entry)
  - [5. Paywall sheet](#5-paywall-sheet)
  - [6. Home-screen widget](#6-home-screen-widget)
- [Content model](#content-model)
- [Premium / subscription model](#premium--subscription-model)
- [What is intentionally *not* in the app](#what-is-intentionally-not-in-the-app)
- [Design notes for the visual pass](#design-notes-for-the-visual-pass)
- [Building & running](#building--running)

---

## The experience at a glance

When a person opens Kigo they see, all on one screen:

1. A **full-bleed image** for today's seasonal word.
2. The **Kigo** itself — the kanji, its hiragana reading, and a short prose note
   on its meaning and significance.
3. A small reading of the current **microseason** (the *Kō*, with its parent
   *Sekki* beneath it).

That is the whole of the main experience. A single, low-key **Upgrade** control
in the corner is the only other affordance — it opens a subscription **Paywall**
that lets the user put a small version of today's image + word on their home
screen as a **widget**.

---

## Core vocabulary

These terms recur throughout the UI and this document. Full definitions live in
[`CONTEXT.md`](./CONTEXT.md).

| Term | Meaning |
| --- | --- |
| **Kigo** (季語) | A traditional Japanese seasonal word. Exactly one is shown per calendar day. |
| **Daily Map** | The perennial mapping from a month-day key (`MM-DD`) to the Kigo shown that day. Covers all 366 days (including `02-29`). The same date always shows the same word. |
| **Microseason / Kō** (候) | One of the 72 micro-seasons of the Japanese almanac, each ~5 days, with a kanji name, reading, and short gloss. The app's secondary display. |
| **Sekki** (節気) | One of the 24 solar terms, each ~15 days. Each Kō belongs to exactly one Sekki, shown beneath it as context. |
| **Today** | The current calendar day in the **device's local time zone**. Drives both the Kigo and the current Kō / Sekki. |
| **Entitlement** | The user's active "widget access" subscription state. Active ⇒ the widget reveals the image. |
| **Premium / Basic** | Display words for the two entitlement states. **Premium** = active entitlement; **Basic** = the free default. There is no separate account — plan ⇔ entitlement state. |
| **Widget Gate** | The rule that the home-screen widget shows the full image only when the entitlement is active; otherwise it shows the Kigo name without the image. |

---

## Screens & surfaces

The app is deliberately small. There is **one** primary screen (Today), two
defined fallback states, one corner control, one modal sheet, and one home-screen
widget with two sizes.

### 1. Today screen (the home experience)

**The entire main app.** Renders today's resolved content as a layered
composition.

**Layers, back to front:**

- **Full-bleed image** — fills the screen edge to edge, sitting behind all text.
  *(Currently a deterministic gradient placeholder derived from the entry's image
  id; real photography/art is a future content concern.)*
- **Text content**, centered:
  - **Kigo kanji** — the seasonal word, the visual focal point (e.g. 初日の出).
  - **Reading** — its hiragana reading (e.g. はつひので).
  - **Description** — a short prose note on the word's meaning and significance,
    center-aligned.
  - A divider, then the **microseason section**:
    - **Kō reading** (primary) — the hiragana reading of the current micro-season.
    - **Sekki reading** (secondary, dimmer) — the parent solar term beneath it.

**Behavior:** the screen is purely a render of already-resolved content — it does
no loading or date logic itself. "Today" is resolved from the device's local
calendar day. There is no navigation away from it except the Upgrade entry's
sheet.

**Accessibility identifiers** (handles for automated UI tests; useful to preserve
through redesign): `kigo.image`, `kigo.kanji`, `kigo.reading`, `kigo.description`,
`microseason.ko`, `microseason.sekki`.

### 2. Loading placeholder

Shown briefly while content is being decoded, or during a reload. A calm,
branded, **non-error** surface — never a blank or broken screen.

- A large progress spinner.
- The text **「読み込み中…」** ("Loading…").

Identifier: `loadingPlaceholder`.

### 3. Unavailable placeholder

Shown if content cannot be loaded at all. Deliberately calm and non-alarming —
**no raw error message, no crash**.

- A leaf SF Symbol (`leaf`).
- The text **「コンテンツは現在利用できません」** ("Content is currently unavailable").

Identifier: `unavailablePlaceholder`.

> The app root switches between exactly three states: **Today**, **Loading
> placeholder**, and **Unavailable placeholder**.

### 4. Upgrade entry

A small, **low-contrast control in the bottom-trailing corner** of the screen,
overlaid on the Today screen. It is deliberately unobtrusive so it does not
disturb the calm nightstand aesthetic — the persuasion lives *inside* the Paywall,
not on the Today screen.

- Labelled **"Upgrade"**.
- Always present, in both Basic and Premium states.
- Tapping it presents the **Paywall** as a sheet (the buy offer for Basic users,
  the active/manage state for Premium users).

Identifier: `paywall.entry`.

> **Design note:** this control is currently a default prominent button purely
> for testability. Per the design intent it should read as a *quiet* affordance,
> not an upsell badge (see [J5](#design-notes-for-the-visual-pass)). This is a
> prime candidate for the visual pass.

### 5. Paywall sheet

The single screen that offers the subscription, presented as a modal sheet from
the Upgrade entry. It is the **only** screen besides Today, and it is never shown
unprompted.

**Contents (Basic / not-yet-subscribed user):**

- **Title** — "Kigo Widgets".
- **Benefits** — the one honest premium benefit: *"Reveal the seasonal
  illustration on your home screen widget."* (`paywall.benefits`)
- **Price** — the subscription price (e.g. ¥300). (`paywall.price`)
- **Duration** — the subscription duration (e.g. monthly). (`paywall.duration`)
- **Buy button** — prominent, labelled "Subscribe". (`paywall.buy`)
- **Restore Purchases button**. (`paywall.restore`)
- **Legal links** — "Terms of Use" and "Privacy Policy", side by side, in small
  secondary text. *(Placeholder URLs for now; required by App Store review of
  auto-renewable subscriptions.)* (`paywall.terms`, `paywall.privacy`)

**Contents (Premium / already-subscribed user):**

- Same title and benefits, but **instead of the buy button** an active/manage
  indicator: a green "Subscription active" label with a seal checkmark.
  (`paywall.manage`)
- The Restore and legal links remain.

Sheet container identifier: `paywall.sheet`.

> **Single product, honest pitch.** There is exactly one subscription product and
> exactly one benefit (revealing the widget image). The Paywall must never
> advertise features the app does not deliver — no extra content, no themes, no
> second tier, no trials or introductory pricing.

### 6. Home-screen widget

A WidgetKit widget that puts today's word on the iOS home screen. Supports two
sizes: **systemSmall** and **systemMedium**.

**What it shows — gated by the entitlement (the "Widget Gate"):**

- **Always:** today's Kigo **kanji** and **reading**.
- **Premium (entitlement active):** additionally reveals the **full-bleed image**
  behind the text — the same visual as the Today screen. This is the one thing
  the subscription unlocks.
- **Basic (entitlement inactive):** the word on a plain background, **no image**.

**Behavior:**

- The widget's timeline current entry is **today's** Kigo, and it automatically
  rolls over to the next day's word at **local midnight**.
- The gallery/placeholder state shows a static sample word (蛍 / ほたる).
- Display name: "Kigo"; description: "Today's seasonal word."

> The widget loads its content independently of the running app (the content file
> is bundled into the extension), and reads the entitlement flag from a shared
> app-group container that the main app writes.

---

## Content model

All content is one document — the **Manifest** (`Resources/manifest.json`,
`schemaVersion` 1.0) — loaded through a `ContentSource` seam so it can later be
served from a real API without touching the UI. It contains:

- **Daily Map** — **366** entries keyed by `MM-DD` (including `02-29`). Each entry:
  ```json
  "01-01": {
    "kanji": "初日の出",
    "reading": "はつひので",
    "description": "The first sunrise of the New Year, greeted from hilltops and shorelines across Japan.",
    "imageId": "kigo-01-01"
  }
  ```
- **Kō** — the **72** micro-seasons. Each: `kanji`, `reading`, `gloss`,
  `sekkiId`, and a `dateRange` (`start`/`end` as `MM-DD`). The 72 ranges are
  contiguous and cover the whole year with no gaps.
  ```json
  {
    "kanji": "東風解凍", "reading": "はるかぜこおりをとく",
    "gloss": "east wind thaws the ice", "sekkiId": "risshun",
    "dateRange": { "start": "02-04", "end": "02-08" }
  }
  ```
- **Sekki** — the **24** solar terms. Each: `id`, `kanji`, `reading`.
  ```json
  { "id": "risshun", "kanji": "立春", "reading": "りっしゅん" }
  ```

**Resolution:** given today's date, the app looks up the Kigo by `MM-DD`, finds
the Kō whose date range contains the date, and reads that Kō's parent Sekki.

---

## Premium / subscription model

- **One** auto-renewable subscription product: `com.tomeitotameigo.kigo.widgets.monthly`.
- It unlocks **exactly one** capability — the widget revealing the day's image.
- **Premium ⇔ entitlement active**; **Basic ⇔ no active entitlement**. There is no
  account, no stored "plan" — the entitlement *is* the plan.
- Purchasing or restoring activates the entitlement, which is shared with the
  widget through an app group so the widget image reveals.
- There is no in-app subscription management UI; for a Premium user the "manage"
  affordance is at most a deep link to Apple's system-managed subscription screen.

---

## What is intentionally *not* in the app

These are hard product boundaries — please don't design surfaces for them:

- **Browsing other days.** Today only. No calendar, history, swiping, or archive.
- **User accounts & sync.** No sign-in, profiles, or cloud sync.
- **Notifications.** No push or local reminders.
- **Sharing & onboarding.** No share sheet, no multi-screen onboarding/tutorial.
  The Paywall sheet is the only screen beyond Today.
- **Subscription complexity.** One product only — no trials, intro pricing,
  promotional/win-back offers, annual plan, or second tier.
- **Invented premium benefits.** Premium reveals the widget image; nothing else.
- **In-app billing management UI.**

---

## Design notes for the visual pass

The current styling is functional placeholder, not the intended look. The
guiding feel ("judgment claims" from the goal doc) for the redesign:

- **J1 — Calm, tasteful wellness object.** Opening the app should feel
  contemplative and uncluttered — a single daily moment dominated by the image
  and the word, closer to a wellness app than a utilitarian calendar. Typography,
  spacing, motion, and overall restraint matter.
- **J2 — Evocative, accurate content & imagery.** The images should suit each
  Kigo and season. *(Images are deterministic gradient placeholders today; real
  art comes later — but the layout should anticipate beautiful full-bleed
  imagery.)*
- **J5 — Calm, on-brand Upgrade entry & Paywall.** The Upgrade entry should read
  as a quiet affordance, **not** an upsell badge, and the Paywall should be
  tasteful and restrained rather than a pushy storefront. The Upgrade entry in
  particular (currently a default prominent button) needs the most attention.

When redesigning, **preserve the accessibility identifiers** listed under each
screen above — the automated UI test suite asserts against them.

---

## Building & running

This is a SwiftUI app + WidgetKit extension + StoreKit 2 project (Swift 6 /
Xcode 26.4), targeting **iOS 26**. The Xcode project is **generated by XcodeGen**
from `project.yml` and is gitignored — never edit `Kigo.xcodeproj` by hand.

```bash
xcodegen generate          # regenerate the project from project.yml
```

Build & run on an iPhone 17 simulator (iOS 26.4.1). For the exact hardened test
invocation and the platform traps to avoid (StoreKit-under-CLI hangs, runtime
pinning), see [`CLAUDE.md`](./CLAUDE.md).

The app's "today" can be pinned for deterministic runs via launch-environment
variables: `KIGO_FAKE_DATE=YYYY-MM-DD`, `KIGO_FAKE_ENTITLEMENT=active|inactive`,
and `KIGO_FAKE_PRICE=<string>`.

### Repository map

| Path | What it is |
| --- | --- |
| `Sources/Kigo/` | The main SwiftUI app (Today screen, Paywall, content loading, entitlement). |
| `Sources/KigoWidgetExtension/` | The WidgetKit extension (timeline, gated widget view). |
| `Resources/manifest.json` | The bundled content Manifest (Daily Map + 72 Kō + 24 Sekki). |
| `Tests/` | Unit and UI test suites (`KigoTests`, `KigoUITests`, `KigoWidgetTests`). |
| `CONTEXT.md` | Domain vocabulary — the authoritative glossary. |
| `docs/GOAL.md` | The goal state and its acceptance/evidence criteria. |
| `docs/adr/` | Architecture Decision Records. |
| `CLAUDE.md` | Operational build/test guide and platform traps. |
