# Kō date-range stored as MM-DD string pair

## Status
Accepted

## Context
Each of the 72 Kō has an approximate active window (~5 days). This window needs to be stored in the manifest so future slices can resolve "which Kō is active today." Several representations were considered:
- ISO-8601 full dates (YYYY-MM-DD) — bind the data to a specific year; wrong for a perennial almanac.
- Day-of-year integers — compact, but opaque and error-prone to maintain.
- `MM-DD` string pair — consistent with the Daily Map keying convention already established; human-readable; year-agnostic; trivially codable.

## Decision
Use a `DateRange` value type with `start` and `end` fields, each an `MM-DD` string, embedded in each `Ko` entry. This mirrors the Daily Map's `MM-DD` key convention and keeps the entire manifest human-readable and year-independent.

## Consequences
- If a more structured representation (e.g. parsed `DateComponents`) is needed later, it can be layered on top without changing the JSON schema.
- Precise date *resolution* logic ("which Kō is today") is still deferred to C4.

## Amendment — C3 slice #11: tiling property and 02-29 boundary handling

### Status
Accepted (amended)

### Context
Slice #11 required that the 72 Kō `dateRange` values tile the full 366-day leap year with no gaps and no overlaps. Two gap days existed in the initial data: `02-29` and `06-05`.

### Decision: linear year model
The 72 Kō ranges are modelled as a **linear span from `01-01` through `12-31`** (366 days inclusive of `02-29`). There is no year-wrap. `start` ≤ `end` is enforced in both the generator and the test.

### Decision: 02-29 absorbed into 霞始靆 (usui second Kō)
`02-29` (leap day) has no canonical place in the traditional Japanese almanac, which predates the Gregorian calendar. It is absorbed into the Kō 霞始靆 ("mist begins to drift", sekkiId `usui`) by extending that Kō's end date from `02-28` to `02-29`. This is the only change needed for February: the following Kō (草木萌動) already starts `03-01`.

Rationale: 霞始靆 is the Kō immediately preceding the March boundary, so absorbing one extra day at its tail is the least-disruptive extension. The traditional almanac's ~5-day windows are approximate anyway; the tiling constraint supersedes almanac precision for data-integrity purposes.

### Decision: 06-05 absorbed into 麦秋至 (shouman third Kō)
`06-05` was uncovered because 麦秋至 ended `06-04` and the next Kō (螳螂生) started `06-06`. The end of 麦秋至 is extended to `06-05`.

### Generator enforcement
`scripts/generate_daily_map.py` now asserts the tiling property at generation time: any future edit that reintroduces a gap or overlap will fail loudly before the file is written.
