#!/usr/bin/env bash
#
# verify-widget.sh — stage the Kigo widget for visual verification on a booted
# simulator, in the *entitled* (Premium → image-showing) state.
#
# Why this exists: a widget's true appearance — including WidgetKit's content
# margins, the thing slice work around `.contentMarginsDisabled()` touches — only
# renders inside WidgetKit's own host (home screen / widget gallery). Rendering
# `KigoWidgetView` in isolation (a SwiftUI preview/host) CANNOT reproduce the
# margins, because they are applied by the widget *configuration*, not the view.
# So verifying anything about widget chrome means looking at a real placed widget.
#
# This script automates everything deterministic up to that point:
#   regenerate → build (app + widget appex) → install → flip the entitlement
#   flag in the shared app-group container → launch once → open Simulator.
#
# The ONE step it cannot do headlessly is the long-press + "Add Widget" gesture
# (no tap tooling: XcodeBuildMCP UI-automation off, no idb/cliclick, and OS-level
# event injection needs accessibility perms the agent harness lacks). After this
# script finishes, place the widget by hand (steps printed at the end) — or, in a
# session with XcodeBuildMCP's UI-automation workflow enabled, drive the tap there.
#
# Re-runnable: safe to run repeatedly. Override SIM_NAME / SIM_OS / SIM_ID via env.
set -euo pipefail

SIM_NAME="${SIM_NAME:-iPhone 17}"
SIM_OS="${SIM_OS:-26.4.1}"            # iOS 26.4 runtime — see CLAUDE.md pin note
APP_ID="com.tomeitotameigo.kigo"
GROUP_ID="group.com.tomeitotameigo.kigo"
ENT_KEY="entitlement.isActive"
DEST="platform=iOS Simulator,name=${SIM_NAME},OS=${SIM_OS}"
DERIVED="build/verify-widget"
APP_PATH="${DERIVED}/Build/Products/Debug-iphonesimulator/Kigo.app"

cd "$(dirname "$0")/.."

# Resolve a SINGLE device UDID and operate on it explicitly. NEVER use `simctl
# boot "iPhone 17"` / `simctl ... booted`: several runtimes (26.2/26.4/26.5) each
# ship a device named "iPhone 17", so by-name boot can start a SECOND sim and
# `booted` then resolves ambiguously — staging the app on one device while the UI
# (and MCP screenshots) land on another. That trap cost a full verification cycle.
# Match the runtime by its 'iOS-<major>-<minor>' key token (e.g. 26.4.1 -> iOS-26-4);
# simctl's positional OS filter does not accept point releases reliably.
SIM_ID="${SIM_ID:-$(xcrun simctl list devices -j \
  | SIM_NAME="$SIM_NAME" SIM_OS="$SIM_OS" python3 -c "import json,sys,os; \
name=os.environ['SIM_NAME']; tok='iOS-'+'-'.join(os.environ['SIM_OS'].split('.')[:2]); \
d=json.load(sys.stdin)['devices']; \
print(next((x['udid'] for rt,rs in d.items() if tok in rt for x in rs if x['name']==name), ''))" 2>/dev/null)}"
if [ -z "${SIM_ID:-}" ]; then
  echo "!! could not resolve a '$SIM_NAME' device on iOS $SIM_OS — check 'xcrun simctl list devices'"
  exit 1
fi
echo "==> target device: $SIM_NAME ($SIM_OS) = $SIM_ID"

echo "==> [1/6] regenerate Xcode project (gitignored; generated from project.yml)"
xcodegen generate >/dev/null

echo "==> [2/6] build app + widget extension for the simulator"
# NB: do NOT pass CODE_SIGNING_ALLOWED=NO here — that strips entitlements, so the
# app-group container is never provisioned and the widget can't read the shared
# flag. Simulator ad-hoc signing embeds the app-group entitlement with no
# provisioning profile, which is exactly what step 5 relies on.
xcodebuild build \
  -scheme Kigo \
  -destination "$DEST" \
  -derivedDataPath "$DERIVED" \
  | tail -3

echo "==> [3/6] boot $SIM_ID (and shut down any other same-named sim) + open Simulator.app"
# Shut down stray devices that share SIM_NAME on OTHER runtimes, so nothing
# competes for the ambiguous `booted` selector elsewhere.
for other in $(xcrun simctl list devices -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; \
print(' '.join(x['udid'] for rs in d.values() for x in rs if x['name']=='$SIM_NAME' and x['state']=='Booted'))" 2>/dev/null); do
  [ "$other" != "$SIM_ID" ] && xcrun simctl shutdown "$other" 2>/dev/null || true
done
xcrun simctl boot "$SIM_ID" 2>/dev/null || true     # no-op if already booted
open -a Simulator

echo "==> [4/6] install the freshly built app (carries the updated widget appex)"
xcrun simctl install "$SIM_ID" "$APP_PATH"

echo "==> [5/6] flip the shared entitlement flag → widget renders the image"
CONTAINER=$(xcrun simctl get_app_container "$SIM_ID" "$APP_ID" "$GROUP_ID")
PLIST="${CONTAINER}/Library/Preferences/${GROUP_ID}.plist"
mkdir -p "$(dirname "$PLIST")"
# Write the boolean directly into the app-group container, then bounce cfprefsd
# in the sim so the value is served from disk (not a stale in-memory cache) the
# next time the widget extension reads UserDefaults(suiteName:).
if /usr/libexec/PlistBuddy -c "Set :${ENT_KEY} true" "$PLIST" >/dev/null 2>&1; then :; else
  /usr/libexec/PlistBuddy -c "Add :${ENT_KEY} bool true" "$PLIST"
fi
xcrun simctl spawn "$SIM_ID" killall -9 cfprefsd 2>/dev/null || true
echo "    set ${ENT_KEY}=true in ${PLIST}"

echo "==> [6/6] launch the app once (triggers WidgetCenter.reloadAllTimelines)"
xcrun simctl launch "$SIM_ID" "$APP_ID" >/dev/null || true

cat <<EOF

==> staged on $SIM_ID. The fixed widget is installed in the entitled (image) state.
    Add the widget to the home screen, then screenshot:
      - With XcodeBuildMCP UI-automation enabled (ENABLED_WORKFLOWS incl.
        'ui-automation' + the arm64 axe wrapper for x64/Rosetta node), drive:
        long_press home → Edit → Add Widget → search "Kigo" → Small / Medium.
      - Manually: long-press home → Edit → Add Widget → "Kigo".
    Capture: xcrun simctl io $SIM_ID screenshot widget.png
EOF
