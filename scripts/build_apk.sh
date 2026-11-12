#!/usr/bin/env bash
# Builds the release APK. Supabase values come from environment variables,
# never from source files.
#
#   export SUPABASE_URL="https://YOUR-PROJECT.supabase.co"
#   export SUPABASE_ANON_KEY="YOUR_ANON_PUBLIC_KEY"
#   bash scripts/build_apk.sh
set -euo pipefail

: "${SUPABASE_URL:?Set SUPABASE_URL first}"
: "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY first}"

cd "$(dirname "$0")/.."

flutter analyze
flutter build apk --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

APK="build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK" ]; then
  echo "APK ready: $(pwd)/$APK"
else
  echo "ERROR: APK was not produced" >&2
  exit 1
fi
