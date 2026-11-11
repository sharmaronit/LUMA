#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
flutter_bin=${FLUTTER_BIN:-"$project_dir/../.tools/flutter/bin/flutter"}
export JAVA_HOME=${JAVA_HOME:-"$project_dir/../.tools/jdk17-home"}
if [ ! -x "$JAVA_HOME/bin/java" ]; then
  echo "Set JAVA_HOME to a JDK 17 or 21 installation." >&2
  exit 2
fi
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.java.home=\"$JAVA_HOME\""
export ANDROID_HOME=${ANDROID_HOME:-"/Users/Apple/Library/Android/sdk"}
cd "$project_dir"
"$flutter_bin" pub get --offline
"$flutter_bin" build apk --no-pub --debug --flavor github --dart-define=ENABLE_SELF_UPDATER=false
