# ADR 0012 — manifest.json bundled into the widget extension

**Status:** Accepted  
**Date:** 2026-06-14  
**Slice:** #73 (C7 Slice 5: Production widget provider renders the entry and reads the real seams)

## Context

The `KigoWidgetProvider` (`TimelineProvider`) runs in the widget extension process,
which is isolated from the Kigo app process. WidgetKit may ask the provider for a
timeline snapshot while the app is not running. `WidgetTimelineBuilder` resolves
today's Kigo from a `Manifest` — the content data loaded from `manifest.json`.

Without `manifest.json` in the widget extension bundle, `BundledContentSource().load()`
fails (`resourceNotFound`) and the provider can only return placeholder entries.

## Decision

Add `Resources/manifest.json` as a resources entry to the `KigoWidgetExtension`
target in `project.yml`:

```yaml
resources:
  - path: Resources/manifest.json
```

`manifest.json` is thus copied into the widget extension bundle at build time by
XcodeGen / the Xcode build system, alongside the existing copy in the Kigo app bundle.

`BundledContentSource` uses `Bundle(for: _BundleAnchor.self)` where `_BundleAnchor`
is a private class defined in `ContentSource.swift`. When `ContentSource.swift` is
compiled into the widget extension, `_BundleAnchor` lives in the widget extension
module, so `Bundle(for:)` resolves to the widget extension bundle — exactly the
bundle that contains the widget's copy of `manifest.json`. No code changes are
needed; only the `project.yml` resources entry is required.

The `manifest.json` file is perennial (date-keyed `MM-DD`, no year component), so
bundling a static copy is correct — the file never changes between app updates.

## Alternatives considered

**Single bundle, read from app bundle**: The widget extension cannot access the
app container's `Bundle.main` reliably when the app is not running. Loading content
from the app bundle at timeline-build time would fail silently in headless invocations.

**App Groups shared file**: Using a shared container (`FileManager` + app group) would
require the app to write the manifest at launch and the widget to read it — two-process
coordination that introduces a race condition on first install. Overkill for static data.

## Consequences

- `manifest.json` is duplicated across the Kigo app bundle and the widget extension
  bundle. At the current manifest size (~100 KB) this is an acceptable cost.
- Any manifest update (future content refresh) requires an app update to reach the
  widget — consistent with the current all-bundled content model (ADR 0001).
- The `project.yml` edit follows ADR 0003 (never hand-edit `Kigo.xcodeproj`;
  always edit `project.yml` and regenerate with `xcodegen generate`).
