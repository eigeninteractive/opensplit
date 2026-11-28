#!/usr/bin/env bash
# Run after prepare.sh and flutter pub get.
set -euo pipefail
cd "$(dirname "$0")/.."

version_code="${1:-}"
if [[ ! "$version_code" =~ ^[1-9][0-9]{0,9}$ ]] ||
  (( version_code > 2100000000 )); then
  echo 'Pass the release Android version code from Play or the GitHub APK.' >&2
  exit 1
fi
test -f fdroid/sqlite3.c

dart run build_runner build
ORG_GRADLE_PROJECT_fdroid=true flutter build apk --release --no-pub \
  --build-number="$version_code" \
  --dart-define=FDROID=true \
  --dart-define=API_BASE_URL=https://opensplit.eigeninteractive.com
