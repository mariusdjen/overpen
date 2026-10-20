#!/bin/bash
# Builds Overpen in Release and installs it in ~/Applications.
# Usage: scripts/build.sh           build, install and launch
#        scripts/build.sh --no-run  build and install only
# Without Config/Local.xcconfig (your DEVELOPMENT_TEAM), the app is signed for this Mac only.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGNING=()
if [ ! -f Config/Local.xcconfig ]; then
  SIGNING=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
fi

xcodebuild -project Overpen.xcodeproj -scheme Overpen -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath build -allowProvisioningUpdates ${SIGNING[@]+"${SIGNING[@]}"} build | grep -E "error|BUILD" || true

APP=build/Build/Products/Release/Overpen.app
[ -d "$APP" ] || { echo "Build failed"; exit 1; }

pkill -x Overpen 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/Overpen.app
cp -R "$APP" ~/Applications/Overpen.app
echo "Installed: ~/Applications/Overpen.app"
[ "${1:-}" = "--no-run" ] || open ~/Applications/Overpen.app
