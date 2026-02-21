#!/bin/bash
set -euo pipefail

APP_NAME="Bones"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "==> Killing existing Bones process..."
pkill -x Bones 2>/dev/null || true
sleep 0.5

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
    -framework QuartzCore \
    -framework AVFoundation \
    -framework Security \
    -O \
    Sources/main.swift \
    Sources/AppDelegate.swift \
    Sources/StatusBarController.swift \
    Sources/SessionController.swift \
    Sources/DragController.swift \
    Sources/DragWindow.swift \
    Sources/HighlightWindow.swift \
    Sources/WindowDetector.swift \
    Sources/WindowTracker.swift \
    Sources/ScreenshotCapture.swift \
    Sources/SkeletonRenderer.swift \
    Sources/FeedbackWindow.swift \
    Sources/ActiveAppState.swift \
    Sources/PersistentHighlightWindow.swift \
    Sources/DebugPanelWindow.swift \
    Sources/AccessibilityHelper.swift \
    Sources/InteractableOverlayWindow.swift \
    Sources/SkeletonPhysics.swift \
    Sources/BoneSoundEngine.swift \
    Sources/BoneBreakAnimation.swift \
    Sources/DogAnimation.swift \
    Sources/SidebarWindow.swift \
    Sources/SidebarDebugView.swift \
    Sources/ChatController.swift \
    Sources/AnthropicClient.swift \
    Sources/KeychainHelper.swift \
    Sources/InteractionTools.swift

echo "==> Copying Info.plist..."
cp Info.plist "${CONTENTS}/Info.plist"

echo "==> Signing app bundle..."
if ! codesign --sign "Bones Dev" --force "${APP_BUNDLE}" 2>/dev/null; then
    echo "    Bones Dev certificate not found; using ad-hoc signing."
    codesign --sign - --force "${APP_BUNDLE}"
fi

echo "==> Build complete: ${APP_BUNDLE}"
echo "    Run with: open ${APP_BUNDLE}"
