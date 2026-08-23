#!/bin/bash
# Archive and export Sunlit for the App Store.
#
# Two things here are load-bearing and are the reason this is a script and not a
# line in a README:
#
#   - No -allowProvisioningUpdates. It overrides the project's Manual signing,
#     picks the Development certificate, and the archive then fails with
#     "profile doesn't include signing certificate". Several apps in this
#     portfolio have been lost to that flag.
#   - TARGETED_DEVICE_FAMILY is forced on the command line. xcodegen has
#     silently dropped it from the generated project before, and an iPad capable
#     binary makes Apple demand an iPad screenshot set and judge an iPad layout
#     nobody has looked at. The built app's UIDeviceFamily is verified below
#     rather than assumed.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME=Sunlit
ARCHIVE="build/Sunlit.xcarchive"
EXPORT="build/export"

xcodegen generate

rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild archive \
  -project Sunlit.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=iOS" \
  TARGETED_DEVICE_FAMILY=1 \
  | tail -5

APP="$ARCHIVE/Products/Applications/Sunlit.app"
python3 - "$APP" <<'PY'
import sys, plistlib, pathlib
app = pathlib.Path(sys.argv[1])
d = plistlib.loads((app / "Info.plist").read_bytes())
fam = d.get("UIDeviceFamily")
print("UIDeviceFamily:", fam, "| version:", d.get("CFBundleShortVersionString"),
      "| build:", d.get("CFBundleVersion"))
assert fam == [1], f"expected iPhone only, got {fam}"
langs = sorted(x.name for x in app.glob("*.lproj"))
print("lproj:", langs)
assert len(langs) == 10, f"expected ten languages, got {len(langs)}: {langs}"
# The city resource must actually be in the bundle. A missing resource turns
# offline search into an empty list with no error anywhere.
cities = app / "cities.bin"
assert cities.exists(), "cities.bin missing from the bundle"
print("cities.bin:", cities.stat().st_size, "bytes")
PY

cat > build/ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>R95M36AU2X</string>
  <key>signingStyle</key><string>manual</string>
  <key>stripSwiftSymbols</key><true/>
  <key>uploadSymbols</key><true/>
  <key>provisioningProfiles</key>
  <dict>
    <key>com.levinschwab.sunlit</key><string>Sunlit App Store</string>
    <key>com.levinschwab.sunlit.widgets</key><string>Sunlit Widgets App Store</string>
  </dict>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist build/ExportOptions.plist \
  | tail -3

ls -la "$EXPORT"
