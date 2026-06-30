# ADR 0019 — Monetization inversion: encounter (free) vs understanding (paid)

**Status:** Accepted
**Date:** 2026-06-30
**Criteria:** C5, C7, C8, C9, C13, C16, C20, C22, C23 (and J3, J5, J8, J9)
**Supersedes (in part):** ADR 0011 (the widget no longer reads the shared entitlement),
ADR 0009's *application* (the injected-seam pattern now also covers notifications, not just StoreKit)
**Reverses:** the original "Premium unlocks exactly one capability — the **Widget Gate** revealing
the image" framing in the north star and CONTEXT.md.

## Context

The product shipped with a single premium capability: an active **Entitlement** revealed the day's
image on the home-screen **Widget**; a non-subscriber's widget showed the Kigo name without the
image. Everything *inside* the app — the image, the Kigo description, the Microseason line, the
Almanac depth — was free.

Three problems with gating the widget image:

1. **The widget is the least-discoverable surface in iOS.** There is no public API to place a
   widget on the home screen, open the widget gallery, or deep-link into edit mode — the user must
   already know to long-press, tap `+`, find the app, and add it. The app cannot drive them there.
   So the one paid benefit lived behind a surface most users never reach, and the app could not
   even point at it.
2. **The free experience was complete and lovely on its own**, leaving no felt reason to pay — the
   paid thing was both invisible *and* inessential.
3. **A static feature unlock fits a one-time purchase, not a subscription.** "Reveal an image on a
   widget" does not obviously justify recurring monthly money; daily-refreshing *content* does.

The category bears this out: widget apps (Widgetsmith et al.) never sell "the widget exists" — they
sell *enhancements* on top of a free daily-valuable core, and they invest in add-a-widget tutorials
precisely because discoverability is the hard part.

## Decision

**Invert the gate. The widget and a new daily reminder become free (the *encounter*); the in-app
understanding layer becomes the paid unlock (the *understanding*).**

- **Free — the encounter (*see* it):** the full-bleed daily image, the Kigo **kanji** and
  **reading**; a fully **ungated Widget** (image + kanji + reading, identical for everyone); and an
  opt-in **daily reminder** (a local notification at 08:00 carrying today's Kigo + a gentle hook).
- **Paid — the understanding (*learn* it):** the Kigo's full **description / significance prose**,
  the **Microseason** display (Kō/Sekki line), and the **Almanac** depth (year-positions, gauges,
  Kō/Sekki prose).
- **The Meaning Gate.** On the Today screen a **Basic** user sees image + kanji + reading and, where
  the description and microseason would sit, a single quiet **Meaning entry** line
  (`meaning.upsell`, e.g. *"what does 蛍 mean? →"*) that opens the Paywall. The Today screen stays
  calm (J1/J5) — one quiet affordance, never a lock badge on the image. A **Premium** user sees the
  description, the microseason line, and the tappable timeline (Almanac) instead, with no upsell
  line.
- **Two entries, one Paywall.** Both the Settings gear (`paywall.entry`) and the `meaning.upsell`
  line present the same `paywall.sheet`; the offer is unchanged in substance (one monthly product),
  only the **Benefits** copy now describes the understanding unlock rather than the widget image.
- **Daily reminder behind an injected seam (the ADR 0009 pattern).** A default-**off**
  `settings.dailyReminder` toggle drives an injectable `NotificationScheduler` protocol. Enabling it
  requests permission *at that moment* (user-initiated) and schedules one repeating daily request at
  08:00 with today's content; disabling cancels it. The scheduling *logic* is gated headlessly
  through an in-memory fake (C23); the real `UNUserNotificationCenter` adapter, the permission
  prompt, and OS delivery are off the headless gating path (J9 / the APNs row of the
  headless-integration-traps catalog).

## What is gated vs not

- **Gated (C22):** Basic Today shows the `meaning.upsell` entry and **not** `kigo.description` /
  `microseason.*`; tapping it presents `paywall.sheet`. Premium Today shows the description +
  microseason line + timeline and **no** `meaning.upsell`. Verified through the real app via
  `KIGO_FAKE_ENTITLEMENT`.
- **Gated (C23):** the `settings.dailyReminder` toggle exists, defaults off, and the scheduling
  logic (enabled ⇒ one daily 08:00 request with today's content; disabled ⇒ none) is correct
  through the injected fake. The UI test asserts presence + default-off only — it must **not**
  tap-enable (that fires the real permission prompt, which hangs headless).
- **Gated (C7, ungated widget):** the widget entry always reveals the image and carries kanji +
  reading regardless of entitlement.
- **Not gated:** that the reminder *feels* gentle and on-brand (J8); the real notification delivery
  end-to-end (J9); that the widget renders correctly on a real home screen for everyone (J3).

## Consequences

- **The Widget Gate is retired.** `KigoWidgetEntry.showsImage` is always true (or removed); the
  widget stops reading the entitlement. The app-group / `EntitlementSharedStore` (ADR 0011) is no
  longer *required* by the widget — its cross-process purpose was sharing the entitlement, which the
  widget no longer needs. The widget still bundles the manifest (C8 step 1–2 unchanged); C8's
  app-group entitlement assertion is dropped. Physically removing the app group / shared store is
  optional cleanup (YAGNI), left to the planner — not gated.
- **The entitlement now gates in-app meaning.** The Today screen must read the entitlement state
  (already injectable via `KIGO_FAKE_ENTITLEMENT`, ADR 0013) to choose between the Meaning entry and
  the understanding layer. C6/C10 (entitlement grant/restore, purchase→activation logic) are
  unchanged — only *what* an active entitlement unlocks changed.
- **Existing understanding-layer UI tests relaunch as Premium.** C5 (TodayScreenUITests), C13
  (MicroseasonAlmanacUITests), C16 (DarkModeUITests), and C20 (LiveLanguageSwitchUITests) assert
  `kigo.description` / `microseason.*`, which are now Premium-only — their launch environment gains
  `KIGO_FAKE_ENTITLEMENT=active`. C18 (TodayLayoutUITests) is unaffected (it asserts only the
  encounter layer + chrome corners).
- **Notifications enter scope** (opt-in, local, single, fixed 08:00). APNs push, a configurable
  time / time-picker, and more than one notification per day stay out of scope.
- **The subscription becomes a more honest recurring value** — daily-refreshing curated
  understanding, not a one-time image reveal.
- **Risk:** a pure-glimpse free tier may satisfy users as ambient beauty without provoking the
  curiosity that converts. Mitigated by keeping the meaning *present at the moment of viewing* (the
  `meaning.upsell` line) and by the free reminder doubling as a daily curiosity hook — without
  cluttering the calm Today screen (J5 judges this balance).
