#!/bin/bash
set -euo pipefail

APP_NAME="Bones"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "==> Cleaning previous build..."
rm -rf "${BUILD_DIR}"

echo "==> Creating .app bundle structure..."
mkdir -p "${MACOS}" "${RESOURCES}"

echo "==> Compiling Swift sources..."
swiftc \
    -o "${MACOS}/${APP_NAME}" \
    -framework AppKit \
    -framework ScreenCaptureKit \
    -framework CoreGraphics \
    -framework ApplicationServices \
    -O \
    Sources/main.swift \
    Sources/AppDelegate.swift \
    Sources/StatusBarController.swift \
    Sources/DragController.swift \
    Sources/DragWindow.swift \
    Sources/HighlightWindow.swift \
    Sources/WindowDetector.swift \
    Sources/ScreenshotCapture.swift \
    Sources/LittleGuyRenderer.swift \
    Sources/FeedbackWindow.swift \
    Sources/ActiveAppState.swift \
    Sources/PersistentHighlightWindow.swift \
    Sources/DebugPanelWindow.swift \
    Sources/AccessibilityHelper.swift \
    Sources/InteractableOverlayWindow.swift

echo "==> Copying Info.plist..."
cp Info.plist "${CONTENTS}/Info.plist"

echo "==> Ad-hoc signing..."
codesign --sign - --force "${APP_BUNDLE}"

echo "==> Build complete: ${APP_BUNDLE}"
echo "    Run with: open ${APP_BUNDLE}"
