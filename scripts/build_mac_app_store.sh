#!/usr/bin/env bash
set -euo pipefail

PROJECT="Getfigdata.xcodeproj"
SCHEME="Getfigdata"
CONFIG="Release"
ARCHIVE_PATH="build/Getfigdata.xcarchive"
EXPORT_PATH="build/appstore"
EXPORT_OPTIONS_PLIST="scripts/exportOptions.plist"

echo "Archiving ${SCHEME} (${CONFIG})..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -archivePath "$ARCHIVE_PATH" archive -allowProvisioningUpdates ${TEAM_ID:+DEVELOPMENT_TEAM=$TEAM_ID}

echo "Exporting IPA for App Store Connect..."

# Build a temporary export options if TEAM_ID is provided
TMP_EXPORT_OPTIONS="$EXPORT_OPTIONS_PLIST"
if [[ -n "${TEAM_ID:-}" ]]; then
  TMP_EXPORT_OPTIONS="build/exportOptions.tmp.plist"
  mkdir -p build
  cat > "$TMP_EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
    <key>manageAppVersionAndBuildNumber</key>
    <true/>
</dict>
</plist>
EOF
fi

xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist "$TMP_EXPORT_OPTIONS" -exportPath "$EXPORT_PATH" -allowProvisioningUpdates

echo "Done. Output in: $EXPORT_PATH"
