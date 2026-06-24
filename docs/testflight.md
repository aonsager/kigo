# Shipping Kigo to TestFlight

How to get Kigo onto your phone via TestFlight and test the **real** purchase flow
in Apple's sandbox (real `Product.purchase()` sheet, restore, renewal — but no money
charged). This is the "less fake than `Products.storekit`" path.

The repo side is already prepared (app icon, encryption-compliance key, signing team,
bundle IDs). What remains is mostly Apple-account work that must be done by hand in
App Store Connect and Xcode.

---

## 0. Prerequisites (one-time)

- Apple Developer Program membership, active, on team **`S25KR8TV8T`** (already the
  `DEVELOPMENT_TEAM` in `project.yml`).
- Signed into Xcode with that Apple ID: **Xcode → Settings → Accounts → add your
  Apple ID**. This is what lets Xcode auto-generate the **Apple Distribution**
  certificate — none exists on this Mac yet (`security find-identity -v -p codesigning`
  shows 0), and Xcode creates it on first archive/distribute.

---

## 1. App Store Connect — create the app record

App Store Connect → **Apps → + → New App**:

- Platform: **iOS**
- Name: **Kigo** (must be globally unique on the App Store — if taken, pick a variant)
- Primary language: **Japanese** (or English — your call)
- Bundle ID: **`com.tomeitotameigo.kigo`** — pick it from the dropdown. If it's not
  listed, register it first at
  [developer.apple.com → Certificates, IDs & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
  with the **App Groups** capability enabled (group `group.com.tomeitotameigo.kigo`).
  Automatic signing in Xcode will also create these on first archive, so you can
  usually skip the manual registration.
- SKU: anything (e.g. `kigo`).

## 2. Accept the Paid Applications Agreement  ⚠️ required for IAP

App Store Connect → **Business** (formerly "Agreements, Tax, and Banking") →
accept the **Paid Applications** agreement and fill in tax/banking.

**In-app purchases silently do not work until this agreement is active**, even in
sandbox/TestFlight. This is the most common "why won't my purchase load" cause.

## 3. Create the subscription in App Store Connect

The product must exist in App Store Connect with an ID that **exactly matches** the
local `Products.storekit`, or it won't load on a TestFlight build.

App Store Connect → your app → **Monetization → Subscriptions**:

1. Create a **Subscription Group**: `Widget Access`.
2. Add a subscription in that group:
   - **Product ID**: `com.tomeitotameigo.kigo.widgets.monthly`  ← must match exactly
   - **Reference Name**: `Widget Access Monthly`
   - **Duration**: 1 month
   - **Price**: ¥300 (JPY) — set the JP price; add others as desired
   - **Localizations**: display name `Widget Access`, description e.g.
     "Reveal today's Kigo image on your home-screen widget. Renews monthly."
     (mirror the JP/EN strings in `Products.storekit`).
   - A subscription needs a localization, a price, and a review screenshot before it
     leaves "Missing Metadata", but it reaches **"Ready to Submit"** — which is all
     that's needed for it to load in **sandbox/TestFlight**. Full App Review of the
     IAP only matters for the public App Store release.

> The numeric `subscriptionGroupID` (`21520757`) and `_applicationInternalID` in
> `Products.storekit` are local placeholders — App Store Connect assigns the real
> ones. They do **not** need to match; only the **Product ID string** must.

---

## 4. Archive and upload (Xcode GUI)

```bash
xcodegen generate && open Kigo.xcodeproj
```

In Xcode:

1. Scheme: **Kigo**. Destination: **Any iOS Device (arm64)** (you cannot archive
   against a simulator).
2. **Product → Archive.** First time, Xcode prompts to create the distribution
   certificate / provisioning profiles — allow it (automatic signing).
3. When the **Organizer** opens: select the archive → **Distribute App** →
   **TestFlight & App Store** (or **TestFlight Internal Only**) → **Upload**.
   Keep the defaults (upload symbols, manage signing automatically).
4. The build appears in App Store Connect → your app → **TestFlight** after a few
   minutes of "Processing".

**Each upload needs a unique build number.** For the next upload, bump
`CFBundleVersion` in `Sources/Kigo/Info.plist` (1 → 2 → …); `CFBundleShortVersionString`
(`1.0`) only changes for user-facing version bumps.

---

## 5. Install on your phone

- App Store Connect → **TestFlight → Internal Testing**. Add yourself as an
  **Internal Tester** (you must be a user on the App Store Connect team; up to 100).
  **Internal builds need no Beta App Review** — available as soon as processing finishes.
  (External testers require a one-time Beta App Review per version.)
- On your iPhone: install the **TestFlight** app from the App Store, sign in with the
  same Apple ID, and install Kigo from it.

---

## 6. Test the purchase in sandbox (the whole point)

On a **TestFlight build, StoreKit automatically uses the sandbox** — the purchase
sheet shows **`[Environment: Sandbox]`** and **no money is charged**. You can use your
normal Apple ID; a separate sandbox tester account is *not* required for TestFlight
(it is for development builds run from Xcode onto a device).

What to verify:
- The subscription **loads** with the ¥300 price (if it shows nothing → agreement not
  accepted, product not "Ready to Submit", or product ID mismatch).
- **Buy** → entitlement flips → the home-screen **widget reveals today's image**
  (the app-group flag path, `EntitlementSharedStore`).
- **Restore Purchases** works on a fresh install.
- **Renewal / expiry**: sandbox auto-renewable subs run on an accelerated clock
  (1 month ≈ 5 minutes, ~6 renewals then auto-cancels), so you can watch a full
  subscribe → renew → lapse cycle in minutes.

Manage / reset sandbox subscriptions on the device:
**Settings → App Store → Sandbox Account** (or **Settings → Developer**) → manage the
subscription to cancel/clear state between test runs.

---

## Replace the placeholder app icon

`Sources/Kigo/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` is a placeholder
(a square crop of `tsuyu.jpg`). Drop in the real **1024×1024, opaque (no alpha)** PNG
at that path — same filename — and re-archive. No `project.yml` change needed.

---

## Common first-upload rejections (all pre-empted in this repo)

| Symptom | Cause | Status |
|---|---|---|
| "Missing required icon file" | No 1024 marketing icon | ✅ fixed — `AppIcon.appiconset` |
| Build stuck on "Missing Compliance" | No export-compliance answer | ✅ fixed — `ITSAppUsesNonExemptEncryption=false` in Info.plist |
| Subscription doesn't load in TestFlight | Paid Apps Agreement not active, or product not in ASC / wrong ID | ⬜ your step (§2, §3) |
| "Redundant binary" on re-upload | Reused build number | bump `CFBundleVersion` |
