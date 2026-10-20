#!/bin/bash
# Archives Overpen and uploads it to App Store Connect.
# Needs an App Store Connect API key in the environment:
#   ASC_KEY_PATH=/path/AuthKey_XXXX.p8 ASC_KEY_ID=XXXX ASC_ISSUER=uuid scripts/release.sh
# and Config/Local.xcconfig with your DEVELOPMENT_TEAM.
# Signing uses the "Mac App Distribution" and "Mac Installer Distribution" certificates
# in your keychain and a Mac App Store provisioning profile (name in PROFILE).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ASC_KEY_PATH:?missing}" "${ASC_KEY_ID:?missing}" "${ASC_ISSUER:?missing}"
[ -f Config/Local.xcconfig ] || { echo "Create Config/Local.xcconfig with DEVELOPMENT_TEAM first"; exit 1; }

AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER")
ARCHIVE=build/Overpen.xcarchive
TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Config/Local.xcconfig)
PROFILE="${PROFILE:-Overpen Mac App Store}"

rm -rf "$ARCHIVE" build/export
xcodebuild -project Overpen.xcodeproj -scheme Overpen -configuration Release \
  -destination "generic/platform=macOS" -archivePath "$ARCHIVE" "${AUTH[@]}" archive | grep -E "error|ARCHIVE" || true
[ -d "$ARCHIVE" ] || { echo "Archive failed"; exit 1; }

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>3rd Party Mac Developer Application</string>
  <key>installerSigningCertificate</key><string>3rd Party Mac Developer Installer</string>
  <key>provisioningProfiles</key><dict>
    <key>com.mariusdjenontin.overpen</key><string>$PROFILE</string>
  </dict>
</dict></plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export "${AUTH[@]}" | grep -E "error|EXPORT|Upload|upload" || true
