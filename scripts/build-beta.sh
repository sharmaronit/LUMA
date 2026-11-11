#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
flutter_bin=${FLUTTER_BIN:-"$project_dir/../.tools/flutter/bin/flutter"}
export JAVA_HOME=${JAVA_HOME:-"$project_dir/../.tools/jdk17-home"}
export ANDROID_HOME=${ANDROID_HOME:-"/Users/Apple/Library/Android/sdk"}
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.java.home=\"$JAVA_HOME\""
cd "$project_dir"
"$flutter_bin" pub get --offline
"$flutter_bin" build apk --no-pub --profile --flavor github \
  --target-platform android-arm,android-arm64 \
  --build-name 1.0.11-beta.4 --build-number 4124 \
  --dart-define=ENABLE_SELF_UPDATER=false
python3 scripts/verify-apk.py build/app/outputs/flutter-apk/app-github-profile.apk
