# ADR 0017 — Remote manifest update behind a versioned, injected seam (real network off the gating path)

**Status:** Accepted
**Date:** 2026-06-21
**Criteria:** C21, J7
**Builds on:** ADR 0001 (ContentSource), ADR 0006 (ContentStore caching), ADR 0016 (content `version`)

## Context

The app should pick up new content without an App Store update: on open, check a **remote,
versioned manifest** and update the **local copy** when it is behind. CONTEXT.md always
anticipated an `HTTPContentSource` "added later"; this is that capability, scoped to the
*client* (no server is built — real hosting stays out of scope).

A real network fetch is a classic headless-hostile seam (GOAL-FORMAT rule 6): a live HTTP call
on the loop's gating path can hang or flake, silently burning a whole iteration, and ADR 0001
already forbids live network in evidence procedures. So the **update logic** must be verifiable
headlessly, with the real fetch fenced off the gating path.

## Decision

**Model remote update as an injectable `RemoteManifestSource` seam, compare a monotonic content
`version`, and apply updates in the background — never blocking the first screen, always
degrading to the local copy on failure.**

- **Seam:** a `RemoteManifestSource` protocol (`func fetchLatest() async throws -> Manifest`).
  Production is a thin `URLSession` adapter against a placeholder `https` URL constant (like the
  legal-link URLs — real hosting is out of scope, swapped in before submission, reported under
  J7). Tests inject an in-memory fake returning a configured manifest/version or throwing.
- **Freshness:** compare the remote manifest's integer `version` (ADR 0016) to the local copy's.
  Update **iff** `remote.version > local.version`. Equal or older ⇒ no change.
- **Apply:** on a newer, **successfully decoded and validated** remote manifest, atomically
  replace the local cached copy (ADR 0006 cache; the app prefers cache over the bundled seed).
  The update is applied to the cache and used on the next resolve; it never blocks launch.
- **Non-blocking:** the ContentStore serves the **local** content immediately and synchronously
  on open; the remote check runs concurrently. The calm first screen never waits on the network.
- **Fail-safe:** any failure — network error, timeout, malformed body, schema/`schemaVersion`
  mismatch, or a `version` not strictly newer — leaves the local copy untouched and surfaces **no
  error to the UI** (consistent with C3's offline behavior).

## What is gated vs off-path

- **Gated (C21), headless via the injected fake:** version-newer ⇒ cache replaced and subsequent
  resolves use the new content; version-not-newer ⇒ unchanged; fetch throws / malformed /
  schema-mismatch ⇒ unchanged and no error surfaces; local content is available immediately,
  independent of the remote check.
- **Residual on-path wiring check:** the production `RemoteManifestSource` is a thin adapter
  correct by inspection; the comparison/apply/fallback logic it feeds is fully gated above.
- **Off the gating path (J7):** the real end-to-end network fetch against a live hosted manifest —
  exercised manually / in a non-loop lane, reported for human review, never a termination gate.

## Consequences

- New content ships without an App Store release; this is also how post-2026 Daily-Map data
  arrives (ADR 0016's out-of-range dates become available once a newer manifest lands).
- The `version` field becomes load-bearing: a remote manifest that forgets to bump it is
  correctly ignored. Generator must bump `version` on every content change.
- Risk: a malicious/corrupt remote manifest. Mitigated by validating shape + `schemaVersion`
  before replacing the local copy, and never deleting the bundled seed (always a fallback).
