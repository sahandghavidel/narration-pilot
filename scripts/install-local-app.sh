#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
APP_ROOT="$HOME/Applications"
APP_PATH="$APP_ROOT/Narration Pilot.app"
LEGACY_APP_PATH="$APP_ROOT/ClipboardReaderMac.app"

cd "$REPO_ROOT"

for process_name in NarrationPilot ClipboardReaderMac clipboard-reader-mac; do
    if pgrep -x "$process_name" >/dev/null; then
        pkill -x "$process_name"
    fi
done

swift build -c release
BINARY_DIR="$(swift build -c release --show-bin-path)"

mkdir -p "$APP_ROOT"
if [[ -d "$LEGACY_APP_PATH" && ! -d "$APP_PATH" ]]; then
    mv "$LEGACY_APP_PATH" "$APP_PATH"
fi

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BINARY_DIR/NarrationPilot" "$APP_PATH/Contents/MacOS/NarrationPilot"
rm -f "$APP_PATH/Contents/MacOS/ClipboardReaderMac"

# Remove resource bundles left by older installers from the app root. macOS
# rejects that nonstandard layout when signing the application.
find "$APP_PATH" -maxdepth 1 -type d -name '*.bundle' -exec rm -rf {} +
find "$APP_PATH/Contents/Resources" -maxdepth 1 -type d -name '*.bundle' -exec rm -rf {} +

# Keep SwiftPM dependency resources in the standard signed-app location.
while IFS= read -r -d '' resource_bundle; do
    cp -R "$resource_bundle" "$APP_PATH/Contents/Resources/"
done < <(find "$BINARY_DIR" -maxdepth 1 -type d -name '*.bundle' -print0)

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Narration Pilot</string>
  <key>CFBundleDisplayName</key>
  <string>Narration Pilot</string>
  <key>CFBundleIdentifier</key>
  <string>local.clipboardreadermac</string>
  <key>CFBundleVersion</key>
  <string>30</string>
  <key>CFBundleShortVersionString</key>
  <string>1.30</string>
  <key>CFBundleExecutable</key>
  <string>NarrationPilot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
    <key>NSExceptionDomains</key>
    <dict>
      <key>host.docker.internal</key>
      <dict>
        <key>NSExceptionAllowsInsecureHTTPLoads</key>
        <true/>
        <key>NSIncludesSubdomains</key>
        <true/>
      </dict>
    </dict>
  </dict>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>local.clipboardreadermac.chapter-import</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>narrationpilot</string>
      </array>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Narration Pilot Chapter JSON</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.json</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

chmod +x "$APP_PATH/Contents/MacOS/NarrationPilot"
codesign --force --deep --sign - "$APP_PATH"
open "$APP_PATH"

echo "Installed Narration Pilot at:"
echo "$APP_PATH"
