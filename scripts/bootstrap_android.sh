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

echo "==> Disabling the release lint-vital check (a known Lint crash in url_launcher_android)"
ROOT_GRADLE="$PROJECT_DIR/android/build.gradle.kts"
[ -f "$ROOT_GRADLE" ] || ROOT_GRADLE="$PROJECT_DIR/android/build.gradle"
cat >> "$ROOT_GRADLE" <<'GRADLE'

// DPI: skip lintVital tasks; the Lint tool crashes on some plugin sources.
subprojects {
    tasks.matching { it.name.contains("lintVital") }.configureEach {
        enabled = false
    }
}
GRADLE

echo "==> Setting compileSdk 36 for the app and all plugins (required by newer plugins)"
sed -i 's/flutter\.compileSdkVersion/36/' "$GRADLE_FILE"
if [[ "$ROOT_GRADLE" == *.kts ]]; then
cat >> "$ROOT_GRADLE" <<'GRADLE'

// DPI: every Android module compiles against API 36.
subprojects {
    if (name != "app") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.compileSdkVersion(36)
        }
    }
}
GRADLE
else
cat >> "$ROOT_GRADLE" <<'GRADLE'

// DPI: every Android module compiles against API 36.
subprojects {
    if (name != 'app') {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.BaseExtension)?.compileSdkVersion(36)
        }
    }
}
GRADLE
fi

echo "==> Adding Firebase (push notifications) config and Gradle plugin"
mkdir -p "$PROJECT_DIR/android/app"
cp "$PROJECT_DIR/firebase/google-services.json" "$PROJECT_DIR/android/app/google-services.json"
SETTINGS_FILE="$PROJECT_DIR/android/settings.gradle.kts"
[ -f "$SETTINGS_FILE" ] || SETTINGS_FILE="$PROJECT_DIR/android/settings.gradle"
if ! grep -q "google-services" "$SETTINGS_FILE"; then
  if [[ "$SETTINGS_FILE" == *.kts ]]; then
    sed -i '0,/^plugins {/s//plugins {\n    id("com.google.gms.google-services") version "4.4.2" apply false/' "$SETTINGS_FILE"
    sed -i '0,/^plugins {/s//plugins {\n    id("com.google.gms.google-services")/' "$GRADLE_FILE"
  else
    sed -i "0,/^plugins {/s//plugins {\n    id 'com.google.gms.google-services' version '4.4.2' apply false/" "$SETTINGS_FILE"
    sed -i "0,/^plugins {/s//plugins {\n    id 'com.google.gms.google-services'/" "$GRADLE_FILE"
  fi
fi

echo "==> Release signing (permanent key from CI secrets; debug key if not set)"
if [ -n "${KEYSTORE_BASE64:-}" ] && [ -n "${KEYSTORE_PASSWORD:-}" ] && [ -n "${KEY_ALIAS:-}" ]; then
  echo "$KEYSTORE_BASE64" | base64 --decode > "$PROJECT_DIR/android/app/dpi-release.jks"
  GRADLE_FILE="$GRADLE_FILE" python3 - <<'PY'
import os, re
path = os.environ["GRADLE_FILE"]
src = open(path).read()
if path.endswith(".kts"):
    block = (
        "signingConfigs {\n"
        "        create(\"release\") {\n"
        "            storeFile = file(\"dpi-release.jks\")\n"
        "            storePassword = System.getenv(\"KEYSTORE_PASSWORD\")\n"
        "            keyAlias = System.getenv(\"KEY_ALIAS\")\n"
        "            keyPassword = System.getenv(\"KEYSTORE_PASSWORD\")\n"
        "        }\n"
        "    }\n    "
    )
    src = src.replace('signingConfig = signingConfigs.getByName("debug")',
                      'signingConfig = signingConfigs.getByName("release")')
else:
    block = (
        "signingConfigs {\n"
        "        release {\n"
        "            storeFile file('dpi-release.jks')\n"
        "            storePassword System.getenv('KEYSTORE_PASSWORD')\n"
        "            keyAlias System.getenv('KEY_ALIAS')\n"
        "            keyPassword System.getenv('KEYSTORE_PASSWORD')\n"
        "        }\n"
        "    }\n    "
    )
    src = src.replace("signingConfig signingConfigs.debug",
                      "signingConfig signingConfigs.release")
src = re.sub(r"(\n\s*)buildTypes \{", lambda m: m.group(1) + block + "buildTypes {", src, count=1)
open(path, "w").write(src)
print("release signing applied to", path)
PY
else
  echo "No keystore secrets found; keeping debug signing."
fi

echo "==> Fetching Dart packages"
cd "$PROJECT_DIR"
flutter pub get

rm -rf "$TMP_DIR"
echo "==> Done. Build with: bash scripts/build_apk.sh"
