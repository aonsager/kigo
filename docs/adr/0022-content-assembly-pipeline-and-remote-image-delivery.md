# ADR 0022 — Content-assembly pipeline and remote image delivery

**Status:** Accepted
**Date:** 2026-07-03
**Relates to:** ADR 0001 (ContentSource seam / placeholder imagery), ADR 0013
(`KIGO_FAKE_*` launch-env injection), ADR 0014 (optional-field forward-compat),
ADR 0016/0018 (absolute 2026 Daily Map, localized content), ADR 0017
(RemoteManifestSource injected network seam), ADR 0019 (ungated widget).
Design brief: `docs/superpowers/specs/2026-07-03-kigo-content-catalog-assembly-design.md`.

## Context

The Daily Map has shipped as **instrumented dummy data** since ADR 0001/0016 — 365
entries whose descriptions carry a `(2026-MM-DD)` stamp to prove per-day reads, over
**gradient placeholder** images (`KigoPlaceholder`, no real photos). The goal now
brings a **real catalog** into scope: 365 real 2026 kigo (kanji, hiragana reading,
EN/JP descriptions) each paired with a royalty-free image.

Two forces shape the decision. First, correctness: kigo word choice, readings, and
seasonal placement come from an authoritative **saijiki** spine, and descriptions are
authored on top — a human-reviewed editorial task, not something a headless loop
certifies (quality stays J2). Second, the **afk loop's evidence discipline**: gated
work must be deterministic, offline, and non-hanging (GOAL.md Constraints; the
"real network calls" row of the headless-integration-traps catalog). Fetching stock
photos, uploading to a CDN, and driving live HTTP all violate that.

## Decision

**Split the work into loop-built machinery (gated) and human-supplied corpus (J).**

1. **Deterministic content-assembly pipeline.** A `scripts/content/` pipeline is the
   single way `Resources/manifest.json` is produced from a reviewed **source CSV**
   (`content/kigo-2026.csv`) — one row per 2026 date. The manifest is **always
   regenerated, never hand-edited**. The pipeline is offline and idempotent; its
   external, network-dependent stages (stock-photo fetch, image re-host) are scripted
   but run **by a human out-of-band** with their own API key + host, never on the
   loop's gating path. The loop builds the pipeline, a validated CSV format,
   validation tooling, a documented LLM-fill workflow, and a **small worked example**
   (~8–12 fully-real, localized rows) that serves as both the gate fixture and the
   template a human extends in a later active session.

2. **`imageBaseURL` — an optional, additive manifest field.** Real images are
   delivered by **remote URL + on-device cache**, not bundled. The manifest gains a
   top-level `imageBaseURL`; the app derives an image's URL as
   `imageBaseURL + "/" + imageId + ".jpg"` (convention, not a per-entry URL — keeps
   the manifest lean and re-hosting a one-line change). The field is **optional**
   (ADR 0014 forward-compat): a manifest without it — including today's bundled
   dummy manifest — still decodes, and a nil `imageBaseURL` means the app shows the
   **gradient placeholder** (graceful degradation, no regression).

3. **`KigoImageSource` — an injected network seam (mirrors ADR 0017).**
   `protocol KigoImageSource { func image(for imageId: String) async -> KigoImage? }`.
   The production adapter builds the URL, checks a size-capped on-disk LRU cache,
   downloads on miss via `URLSession`, caches, and returns the image; `nil` ⇒ the
   caller shows the placeholder. Tests inject an **in-memory fake**; the real network
   fetch is **off the gating path** (J10), exactly as the RemoteManifestSource network
   fetch is (J7). The residual on-path wiring (URL is well-formed; the adapter returns
   without throwing against a stubbed offline `URLProtocol`) is asserted, so a green
   fake can't hide a mis-wired adapter.

4. **`KIGO_FAKE_IMAGE=loaded|none` launch-env injection (extends ADR 0013).** So the
   Today screen's real-image-vs-placeholder render is verifiable in a reachable-app UI
   test deterministically and headlessly — the same pattern as
   `KIGO_FAKE_DATE`/`KIGO_FAKE_ENTITLEMENT`.

5. **The widget stays on the gradient placeholder.** Real photos in the widget would
   require pre-fetching into a shared app-group container the widget reads —
   reintroducing the dependency ADR 0019 deliberately removed. Deferred to a future
   slice with its own ADR; real photos are an **in-app** enhancement only for now.

6. **The date-stamp instrumentation is retired as real content lands.** Real prose
   does not carry a `(2026-MM-DD)` suffix, so C4/C20 no longer verify per-day reads
   by the stamp: C4 verifies **content-equality** (the resolved entry equals the
   manifest entry for that key — a check it already half-performed) and C20 verifies
   the description text **changes ja→en live**. Both checks pass against dummy *and*
   real data, so the transition can't silently break them.

## Why not …

- **Bundle the images.** 365 photos add 50–150 MB to the app and a heavy git repo,
  and every content refresh would ship an app update. Remote + cache keeps the app
  light and composes with the existing `version`/`RemoteManifestSource` refresh path.
- **Per-entry `imageURL`.** 365 redundant URLs bloat the manifest and every diff;
  the `imageBaseURL + imageId` convention is leaner and host-portable.
- **Let the loop fetch/host images or drive live HTTP on the gating path.** It hangs
  or flakes headless (trap catalog), needs secrets + infra the loop can't safely hold,
  and the sandbox blocks those hosts. Scripted + human-run + injected-fake is the only
  discipline-preserving option.
- **Loop-generate the full 365-entry corpus.** Non-deterministic, only shape-gateable,
  and JP readings need human review regardless. A worked example + turnkey scaffolding
  yields better readings (human-in-the-loop) and a crisp, gateable milestone.

## Consequences

- A static image host and a stock-photo API key are **human-supplied inputs** the
  pipeline documents and the human provides; the real end-to-end image load is J10.
- `Resources/manifest.json` stays the bundled seed/fallback; the real corpus lands
  when the human runs the fill + assemble, at which point quality is judged (J2).
- New criteria: C24 (pipeline + scaffold + worked example), C25 (`KigoImageSource`
  seam + cache + fallback logic), C26 (Today renders the remote image with placeholder
  fallback). New judgment claim J10 (real images load from the CDN end-to-end).
