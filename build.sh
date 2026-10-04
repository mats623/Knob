#!/bin/zsh
# Builds Knob.app. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Knob.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library \
  -target arm64-apple-macos14.2 \
  -import-objc-header Sources/Bridge.h \
  Sources/*.swift \
  -framework IOKit -framework CoreAudio -framework AudioToolbox -framework ServiceManagement \
  -o "$APP/Contents/MacOS/Knob"

cp Resources/Info.plist "$APP/Contents/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Knob 2>/dev/null || true
  rm -rf /Applications/Knob.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Knob.app"
fi
