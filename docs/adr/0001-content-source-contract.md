# Content is loaded through a ContentSource seam against a frozen Contract

All content (the Daily Map of Kigo, the 72 Kō, the 24 Sekki, and per-Kigo image
slots) is read through a `ContentSource` protocol. The shape of the served data —
the **Contract** — is frozen now: a single `manifest.json` plus image slots. For
this milestone the only implementation is `BundledContentSource`, which reads
files generated and committed into the repo; an `HTTPContentSource` pointed at a
real API path is a deliberately deferred later implementation.

We chose this because the eventual source of truth is a separate API, but standing
up and deploying that server is out of scope for this app's build loop, and tests
must be deterministic with no live network. The protocol seam lets the UI, caching,
and widget code be built and verified now against bundled fixtures, then swap to
the network later by selecting a different `ContentSource` — no UI changes. This is
hard to reverse cheaply (it shapes the whole data layer), so it is recorded here.
