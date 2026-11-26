#!/usr/bin/env bash
# Run in a disposable source checkout before running Flutter's dependency resolver.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -e .dart_tool || -e android/key.properties ]]; then
  echo 'Prepare F-Droid from a fresh source checkout without local signing keys.' >&2
  exit 1
fi

archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT
# SQLite 3.54.1, the patch release of the locked Dart package’s SQLite 3.54.
curl --fail --silent --show-error --location \
  https://sqlite.org/2026/sqlite-amalgamation-3540100.zip --output "$archive"
python3 - "$archive" <<'PYTHON'
import hashlib
import sys
from pathlib import Path
from zipfile import ZipFile

archive = Path(sys.argv[1])
expected = "92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30"
if hashlib.sha3_256(archive.read_bytes()).hexdigest() != expected:
    raise SystemExit("SQLite archive does not match the published SHA3-256.")
with ZipFile(archive) as contents:
    Path("fdroid/sqlite3.c").write_bytes(
        contents.read("sqlite-amalgamation-3540100/sqlite3.c")
    )
PYTHON

# Flutter loads native plugins from the Pub dependency graph. A runtime flag
# alone would leave Firebase and Play libraries in the Android build.
awk '
  /^  (firebase_core|firebase_messaging|flutter_local_notifications|google_sign_in|google_sign_in_web|in_app_update|in_app_review): / {
    removed++
    next
  }
  /^    - assets\/google_sign_in\/google-sign-in-(light|dark)\.png$/ { next }
  { print }
  END { if (removed != 7) exit 1 }
' pubspec.yaml > pubspec.fdroid.yaml
cat >> pubspec.fdroid.yaml <<'YAML'

hooks:
  user_defines:
    sqlite3:
      source: source
      path: fdroid/sqlite3.c
YAML
mv pubspec.fdroid.yaml pubspec.yaml

cp -R fdroid/lib/. lib/
rm lib/data/push/background_handler.dart lib/data/push/notification_channel.dart
