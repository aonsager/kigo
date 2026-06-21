# ADR 0016 — Daily Map re-keyed to absolute 2026 dates (perennial keying reversed for the Daily Map only)

**Status:** Accepted
**Date:** 2026-06-21
**Criteria:** C2 (amended), C4 (amended), C19
**Supersedes (in part):** ADR 0005 (perennial `MM-DD` Daily Map keying)

## Context

The original Contract (ADR 0001 / ADR 0005) keyed the **Daily Map** by `MM-DD`, making it
**perennial**: the same Kigo shows on a given calendar day every year (north star: "the same
Kigo is shown to everyone on a given date … decided in advance by a perennial Daily Map").

Two new product goals change what the Daily Map is for, for now:

1. The data pipeline (and especially the new **remote manifest update**, ADR 0017) needs to
   be **verifiably reading the right per-day record**. The cleanest way to confirm "the entry
   I'm seeing is genuinely today's" is to stamp each entry's description with its own date and
   key the map by the **absolute date** being resolved.
2. The current dataset is **instrumented dummy content** ("data for every day in 2026"), not
   the final curated corpus. Year-specific keys make that explicit and testable.

The **72 Kō / 24 Sekki** are a different kind of data: the microseasons genuinely recur every
year, anchored to solar terms. They are **not** affected by this decision.

## Decision

**Re-key the Daily Map by absolute `YYYY-MM-DD`, populated for every day of 2026 (365 entries,
no `02-29`). Keep the Kō/Sekki structures perennial (`MM-DD` date ranges).**

- Daily Map keys become `2026-01-01 … 2026-12-31`; resolution looks up today's absolute date.
- Each `DailyMapEntry` description (in **both** `ja` and `en`, per ADR 0018) **contains its own
  ISO date** (`2026-MM-DD`), so a UI/integration test can assert the rendered entry matches the
  resolved date — the "is the correct date being read?" instrumentation the goal asks for.
- A monotonic integer content **`version`** is added at the manifest top level (distinct from
  `schemaVersion`, which tracks shape) for the remote-update freshness comparison (ADR 0017).
- **Out-of-range dates** (any date the manifest has no entry for — e.g. a 2027 date before a
  remote update ships new data) resolve to the existing **defined "content unavailable" state**
  (ADR 0006 / C3), never a crash and never a silently-wrong day.
- Kō/Sekki keep perennial `MM-DD` ranges; the Almanac resolver (C11) is unchanged.

## Consequences

- **Reverses the "same Kigo every year" promise** for the Daily Map. This is acceptable while
  the dataset is dummy/instrumented and the app is single-year (2026); the remote-update channel
  (ADR 0017) is how future years' data arrives. Restoring perennial behavior, or a hybrid, is a
  later goal amendment — not loop work.
- **C2** changes from "366 `MM-DD` keys incl. `02-29`" to "365 `2026-MM-DD` keys covering every
  day of 2026". **C4** resolves the Kigo by absolute date and gains an out-of-range→unavailable
  case; its leap-day check moves to Kō resolution (perennial ranges), since 2026 has no `02-29`.
- The generator and `BundledContentSource` fixtures are regenerated together; the remote and
  bundled manifests share the same shape.
- Risk: losing the `02-29` Daily-Map edge case. Mitigated by keeping a leap-day case in the
  perennial **Kō** resolution path (a leap-year date still falls inside a Kō range).
