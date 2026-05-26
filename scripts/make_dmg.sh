#!/usr/bin/env bash
SCHEME="Getfigdata"
APP_NAME="Getfigdata"
PROJ="Getfigdata.xcodeproj"
REL_DIR="Products/Release"
DBG_DIR="Products/Debug"
APP_REL="$REL_DIR/$APP_NAME.app"
APP_DBG="$DBG_DIR/$APP_NAME.app"
STAGE="dmgstage"
DMG_NAME="$APP_NAME.dmg"

xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release build || true
APP_PATH="$APP_REL"
if [ ! -d "$APP_PATH" ]; then
  xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug build || true
  APP_PATH="$APP_DBG"
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"
rm -f "$DMG_NAME"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -imagekey zlib-level=9 "$DMG_NAME"
rm -rf "$STAGE"
