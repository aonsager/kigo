# ADR 0004: Widget Extension Embedding and Info.plist Requirements

## Status

Accepted (slice #3 — widget extension target)

## Context

Adding the `KigoWidgetExtension` WidgetKit app-extension target to the Xcode project
(via XcodeGen `project.yml`) requires embedding the extension in the `Kigo` app and
configuring its `Info.plist` correctly so the simulator installer accepts it.

Two non-obvious decisions arose during implementation.

## Decisions

### 1. Embedding via XcodeGen dependency with `embed: true`

XcodeGen embeds app-extension targets automatically when listed as a dependency of
the parent app with `embed: true`:

```yaml
targets:
  Kigo:
    dependencies:
      - target: KigoWidgetExtension
        embed: true
```

This places the `.appex` bundle in `Kigo.app/PlugIns/` at build time, which is the
standard location for app extensions on iOS. No `SKIP_INSTALL` or manual copy-phase
configuration is required.

### 2. Full Info.plist required for the extension (no auto-generation)

When a custom `INFOPLIST_FILE` is provided, Xcode does **not** inject
`PRODUCT_BUNDLE_IDENTIFIER` or other standard bundle keys automatically. The extension
`Info.plist` must explicitly include:

| Key | Value | Why required |
|-----|-------|--------------|
| `CFBundleIdentifier` | `$(PRODUCT_BUNDLE_IDENTIFIER)` | `embeddedBinaryValidationUtility` reads the plist directly; without this key the identifier reads as `(null)` and the prefix check fails even when the build setting is correct |
| `CFBundleVersion` | `1` | Simulator `installd` requires a non-empty `bundleVersion` in the placeholder attributes for app-extension bundles |
| `CFBundleName` | `$(PRODUCT_NAME)` | Simulator `installd` rejects the `.appex` with "does not have a CFBundleName key" if omitted |
| `CFBundleExecutable` | `$(EXECUTABLE_NAME)` | Needed for the system to locate the extension binary |
| `CFBundlePackageType` | `XPC!` | Canonical package type for app extensions |
| `NSExtension.NSExtensionPointIdentifier` | `com.apple.widgetkit-extension` | Required to declare the extension point; WidgetKit uses this to register the bundle |

The `embeddedBinaryValidationUtility` Xcode step checks that the embedded `.appex`
bundle ID is prefixed by the parent app's bundle ID using the *built* Info.plist
(not build settings), so all substitution variables must resolve correctly at build
time.

### 3. No entitlements file required for CODE_SIGNING_ALLOWED=NO builds

Building unsigned (via `CODE_SIGNING_ALLOWED=NO`, both at global settings level and
per-target) does not require any entitlements file. App Group entitlements are
explicitly deferred to C6/C7 per the slice specification.

### 4. Explicit KigoWidgetExtension scheme required

XcodeGen does not auto-create per-target schemes when an explicit top-level `schemes:`
block exists. The `KigoWidgetExtension` scheme must be declared in `project.yml`'s
`schemes:` block for `xcodebuild -scheme KigoWidgetExtension` to resolve.

## Consequences

- The extension's `Info.plist` is a full (if minimal) bundle descriptor, not just the
  `NSExtension` stanza. Future changes to bundle metadata (version bumping, display
  name) should update this file.
- No app group entitlements are wired; this is intentional and deferred.
- `xcodebuild build -scheme KigoWidgetExtension … CODE_SIGNING_ALLOWED=NO` and
  `xcodebuild test -scheme Kigo … CODE_SIGNING_ALLOWED=NO` both succeed.
