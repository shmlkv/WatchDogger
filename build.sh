#!/bin/bash
set -euo pipefail

APP="WatchDogger"
APP_DIR="${APP}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "==> Cleaning..."
rm -rf "${APP_DIR}"

echo "==> Creating app bundle structure..."
mkdir -p "${MACOS}" "${RESOURCES}"

echo "==> Copying Info.plist..."
cp Info.plist "${CONTENTS}/Info.plist"

echo "==> Compiling app..."
swiftc -O -o "${MACOS}/${APP}" \
    -framework Cocoa \
    -framework UserNotifications \
    -framework SwiftUI \
    -framework ServiceManagement \
    -framework IOKit \
    main.swift SettingsWindow.swift

echo "==> Generating icons..."
swift make-icon.swift

echo "==> Building icon set..."
iconutil -c icns "${RESOURCES}/AppIcon.iconset" -o "${RESOURCES}/AppIcon.icns"

echo "==> Generating alert sound..."
swift make-sound.swift

echo "==> Signing app..."
codesign --force --deep --sign - "${APP_DIR}"

echo "==> Done! ${APP_DIR} is ready."
