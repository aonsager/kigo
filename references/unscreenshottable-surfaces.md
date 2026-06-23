# Unscreenshottable Surfaces Catalog

Slices may only claim `screenshot_evidence: Exempt` by citing an entry from this catalog.
An exemption is valid iff the surface genuinely cannot be screenshotted even by
host-rendering the real view + real data path.

## Catalog entries

### content-layer-no-ui

**ID:** `content-layer-no-ui`

**Description:** A content-layer milestone that modifies bundled data (e.g. JSON manifest
fields) and writes decoder-completeness tests, but adds no new UI-rendered surface and
no existing UI surface exposes the new content fields during the milestone's scope.
The residual on-path gate replaces the screenshot: the test suite loads the committed
manifest through the real production content path (no injected fixture) and asserts the
new content fields structurally (e.g. via `assertNoCJK`).

**Example:** C19 — populates English `LocalizedText` fields in `Resources/manifest.json`
and writes `ContentLocalizationCompletenessTests`; the English fields are not rendered
until C20, so there is no app surface to screenshot.

**Conditions for valid use:**
- The milestone is purely content + decoder tests (no new view, no new binding).
- The UI views in scope bind to a different language/field than the one being populated
  (the new content is not rendered until a downstream milestone).
- The completeness tests load via the real production content path.
