#!/usr/bin/env bash
# Creates the Android platform folder (Gradle files, manifest, icons) using the
# Flutter SDK, then applies DPI-specific settings. Run once after cloning.
#
#   bash scripts/bootstrap_android.sh
#
# Requires: flutter (stable 3.27+) on PATH, JDK 17+, Android SDK.
set -euo pipefail

APP_ID="bd.ac.dpi.departmenthub"
APP_LABEL="DPI Department Hub"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

command -v flutter >/dev/null || { echo "ERROR: flutter not found on PATH"; exit 1; }

echo "==> Generating Android scaffold in a temp folder"
flutter create --platforms=android --org bd.ac.dpi --project-name dpi_department_hub "$TMP_DIR/scaffold" >/dev/null

if [ -d "$PROJECT_DIR/android" ]; then
  echo "android/ already exists; leaving it untouched."
else
  cp -r "$TMP_DIR/scaffold/android" "$PROJECT_DIR/android"
fi

GRADLE_FILE="$PROJECT_DIR/android/app/build.gradle"
[ -f "$GRADLE_FILE" ] || GRADLE_FILE="$PROJECT_DIR/android/app/build.gradle.kts"

echo "==> Setting applicationId to $APP_ID"
if [[ "$GRADLE_FILE" == *.kts ]]; then
  sed -i -E "s/applicationId = \".*\"/applicationId = \"$APP_ID\"/" "$GRADLE_FILE"
else
  sed -i -E "s/applicationId \".*\"/applicationId \"$APP_ID\"/" "$GRADLE_FILE"
fi

MANIFEST="$PROJECT_DIR/android/app/src/main/AndroidManifest.xml"
echo "==> Setting app label and INTERNET permission in the main manifest"
sed -i -E "s/android:label=\"[^\"]*\"/android:label=\"$APP_LABEL\"/" "$MANIFEST"
if ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
  # Release builds do not merge the debug/profile INTERNET permission.
  sed -i "s#<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">#&\n    <uses-permission android:name=\"android.permission.INTERNET\"/>#" "$MANIFEST"
fi

echo "==> Fetching Dart packages"
cd "$PROJECT_DIR"
flutter pub get

rm -rf "$TMP_DIR"
echo "==> Done. Build with: bash scripts/build_apk.sh"
