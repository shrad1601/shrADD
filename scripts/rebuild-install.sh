#!/bin/bash
# Rebuilds shrADD. and installs it on the iPhone, which resets the free Apple
# ID's 7-day signing clock. Meant to run from launchd a few times a week;
# if the phone isn't reachable it logs that and exits cleanly.

set -u

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${SHRADD_DEVICE:-00008120-000E1DE60A38A01E}"
BUNDLE_ID="com.shraddhasriram.expensetracker.app"
BUILD_DIR="$HOME/Library/Caches/shrADD-build"
LOG="$HOME/Library/Logs/shrADD-rebuild.log"

exec >>"$LOG" 2>&1
echo "=== $(date) ==="

if ! xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICE\|$(echo "$DEVICE" | tr -d '-')"; then
  echo "Device $DEVICE not found (phone off, locked, or not on Wi-Fi). Skipping."
  exit 0
fi

cd "$PROJECT_DIR" || exit 1

if ! xcodebuild -project ExpenseTracker.xcodeproj -scheme ExpenseTracker \
    -destination 'generic/platform=iOS' -configuration Debug \
    -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates build; then
  echo "Build failed."
  exit 1
fi

APP="$BUILD_DIR/Build/Products/Debug-iphoneos/ExpenseTracker.app"

if xcrun devicectl device install app --device "$DEVICE" "$APP"; then
  echo "Installed OK."
else
  echo "Install failed (is the phone unlocked and on the same Wi-Fi?)."
  exit 1
fi
