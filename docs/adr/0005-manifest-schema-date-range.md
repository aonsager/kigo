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
- Precise boundary logic (e.g. leap-year edge cases, ranges spanning December→January) is deferred to the slice that implements date resolution (C4). The `DateRange` fields are stored but not interpreted in this slice.
- If a more structured representation (e.g. parsed `DateComponents`) is needed later, it can be layered on top without changing the JSON schema.
