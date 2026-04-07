#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="$ROOT_DIR/bruh.xcodeproj"
SCHEME="bruh"
DEVICE_NAME="${1:-iPhone 17}"
DERIVED_DATA_PATH="$ROOT_DIR/.build"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/bruh.app"
BUNDLE_ID="com.example.bruh"

echo "Booting simulator: $DEVICE_NAME"
xcrun simctl boot "$DEVICE_NAME" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_NAME" -b

echo "Building $SCHEME for $DEVICE_NAME"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

echo "Installing app on $DEVICE_NAME"
xcrun simctl install "$DEVICE_NAME" "$APP_PATH"

echo "Launching $BUNDLE_ID"
xcrun simctl launch "$DEVICE_NAME" "$BUNDLE_ID"
