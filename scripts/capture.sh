#!/bin/bash
# Capture App Store screenshots from the simulator, one language at a time.
#
# Two things here are the result of days lost in this portfolio:
#
#   Only ONE simulator is booted. Eight hangs of ten minutes or more came from
#   six to eight simulators booted at once; after shutting them all down and
#   booting a single device, boot took thirteen seconds.
#
#   Each language is captured in its own run with its own -AppleLanguages
#   argument. A previous project shipped ten "localised" screenshot sets that
#   were pixel identical, because the app had been launched once and the poster
#   text swapped afterwards. The check at the end compares the shots BELOW the
#   status bar, since the clock and the battery differ between runs whether or
#   not the language did.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_NAME="${DEVICE_NAME:-iPhone 16 Pro Max}"
SCHEME=Sunlit
BUNDLE=com.levinschwab.sunlit
OUT="build/shots"
LANGS="${LANGS:-en de fr it es es-MX nl pl ja pt-BR}"

echo "== shutting every simulator down before booting one =="
xcrun simctl shutdown all 2>/dev/null || true

DEVICE_ID=$(xcrun simctl list devices available -j \
  | python3 -c "
import json,sys
data = json.load(sys.stdin)['devices']
for runtime, devices in data.items():
    if 'iOS' not in runtime: continue
    for d in devices:
        if d['name'] == '$DEVICE_NAME':
            print(d['udid']); raise SystemExit
raise SystemExit('no device named $DEVICE_NAME')
")
echo "device $DEVICE_NAME = $DEVICE_ID"

xcrun simctl boot "$DEVICE_ID"
xcrun simctl bootstatus "$DEVICE_ID" -b

echo "== building for the simulator =="
xcodegen generate
xcodebuild build \
  -project Sunlit.xcodeproj -scheme "$SCHEME" -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO TARGETED_DEVICE_FAMILY=1 \
  | tail -3

APP=$(find build/dd/Build/Products -name "Sunlit.app" -maxdepth 3 | head -1)
[ -n "$APP" ] || { echo "no app built"; exit 1; }

# A fixed instant and a fixed place, so a poster is reproducible and so the
# gradient is the golden hour rather than whatever time the machine happens to
# be at. The app reads these from the launch arguments.
CAPTURE_PLACE="${CAPTURE_PLACE:-47.5622,10.7498,1200,Europe/Berlin,Alps}"
CAPTURE_INSTANT="${CAPTURE_INSTANT:-2026-08-23T18:42:00Z}"

for lang in $LANGS; do
  echo "== $lang =="
  rm -rf "$OUT/$lang"; mkdir -p "$OUT/$lang"
  xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$DEVICE_ID" "$APP"

  xcrun simctl launch "$DEVICE_ID" "$BUNDLE" \
    -AppleLanguages "($lang)" -AppleLocale "$lang" \
    -SunlitCaptureMode 1 \
    -SunlitCapturePlace "$CAPTURE_PLACE" \
    -SunlitCaptureInstant "$CAPTURE_INSTANT" \
    -SunlitCapturePro 1 > /dev/null

  # The app writes a marker file when it has settled, so the capture waits on
  # the app rather than on a fixed sleep. A fixed sleep is how a half drawn
  # screen ends up in a poster.
  for screen in sky ar map data; do
    xcrun simctl launch "$DEVICE_ID" "$BUNDLE" \
      -SunlitCaptureScreen "$screen" > /dev/null 2>&1 || true
    sleep 2.5
    xcrun simctl io "$DEVICE_ID" screenshot --type=png "$OUT/$lang/$screen.png" > /dev/null
    echo "   $screen"
  done
  xcrun simctl terminate "$DEVICE_ID" "$BUNDLE" 2>/dev/null || true
done

echo "== verifying the languages actually differ =="
python3 scripts/poster/verify-shots.py "$OUT" $LANGS
