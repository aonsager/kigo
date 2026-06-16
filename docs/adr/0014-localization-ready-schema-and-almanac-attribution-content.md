# ADR 0014 — Localization-ready content schema; almanac & attribution content added, English deferred

**Status:** Accepted
**Date:** 2026-06-16
**Criteria:** C12 (almanac/attribution content + localization-ready schema), C11, C13, C14, C15

## Context

The Asagiri revamp (see `docs/GOAL.md`, the `Kigo Revamp.dc.html` handoff) introduces
three things the frozen Contract (ADR 0001) does not yet carry:

1. The **Microseason Almanac** renders a prose **description** per Kō and per Sekki, and a
   **gloss** per Sekki (Kō already has a gloss; Sekki has only `id/kanji/reading`).
2. The **Image Attribution panel** renders per-image **title / credit / license** metadata.
3. A **Language preference** (JP default / EN) is being added. The product intent is full
   JP⇄EN content eventually, but translating 366 Daily Map + 72 Kō + 24 Sekki descriptions
   is out of scope for this goal — only the *mechanism* and the app's *UI-chrome* strings
   switch now (the kanji content names never translate).

The Contract was deliberately "frozen" so content could later move to a real API
(`HTTPContentSource`) without touching the UI. Adding fields is therefore a schema change
that must be made once, deliberately, in a forward-compatible way — not drifted into.

## Decision

**Extend the Contract once, now, to be localization-ready, and add the new content fields
as required Japanese plus optional English:**

- `Ko` gains a required `description` (Japanese prose). `Sekki` gains a required `gloss`
  and `description`. Each image (carried per `DailyMapEntry`) gains a required
  `attribution { title, credit, license }`.
- Every user-facing free-text field that will eventually localize (`description`, `gloss`,
  attribution strings) is decoded through a shape that carries an **optional English
  value** alongside the required Japanese one, such that the Manifest decodes successfully
  **whether or not the English value is present**. Adding English content later is then a
  data change, not a schema break.
- `schemaVersion` is bumped to reflect the new shape.

**What is gated vs deferred:**

- **Gated (C12):** the *presence and well-formedness* of the required Japanese fields for
  all entries, and that the optional-English shape decodes both with and without the
  English value. The **Almanac positions** (Kō N/72, Sekki M/24, day-within-Kō,
  Kō-within-Sekki) are **derived** by the resolver from existing `dateRange`/ordering data
  — they are not stored (C11).
- **Not gated:** the literary quality of the descriptions/glosses and the suitability of
  attribution values (images are placeholders) — reported as judgment claims J2/J6.
- **Deferred:** populating the English content; only the schema-readiness and the
  UI-chrome English strings ship in this goal (C15).

**Indexing:** Almanac year-positions are **1-indexed** (梅子黄 = 27/72), matching the lit
timeline tick — overriding the mockup's literal "26/72" (CONTEXT.md flagged ambiguity).

## Consequences

- The Contract changes once, cleanly, instead of repeatedly. `HTTPContentSource` will serve
  the same shape; `BundledContentSource` and the generator are updated together.
- C2's existing validation (Daily Map / Kō / Sekki structural completeness) is unchanged;
  C12 is an additive sibling so old assertions keep their meaning.
- Tests that hand-build fixtures must include the new required fields; a localization decode
  test pins the optional-English forward-compatibility so a later EN rollout cannot silently
  regress the schema.
- Risk: over-building localization before it is needed. Mitigated by gating only the
  *shape* (decodes with/without EN) — no English content, no language-aware resolution path,
  and no region/date/number localization (explicitly out of scope; see CONTEXT.md
  **Language preference**).
