#!/usr/bin/env bash
# Idempotently patch the Flutter SDK's gradle files to use Google's Maven
# Central mirror (repo.maven.apache.org returns 403 for this workstation IP).
# Run this after `flutter upgrade` if builds start failing with 403 errors.
set -euo pipefail

FLUTTER_SDK="${FLUTTER_SDK:-$(dirname "$(dirname "$(command -v flutter)")")}"
GRADLE_DIR="$FLUTTER_SDK/packages/flutter_tools/gradle"
MIRROR='maven("https://maven-central.storage-download.googleapis.com/maven2/")'

if [ ! -d "$GRADLE_DIR" ]; then
  echo "error: $GRADLE_DIR not found" >&2
  exit 1
fi

patch_file() {
  local f="$1" indent="$2"
  if grep -q 'storage-download' "$f"; then
    echo "already patched: $f"
    return
  fi
  if grep -q 'mavenCentral()' "$f"; then
    sed -i "s|^${indent}mavenCentral()|${indent}${MIRROR}\n${indent}mavenCentral()|" "$f"
    echo "patched: $f"
  else
    echo "no mavenCentral() in: $f (skipped)"
  fi
}

# dependencyResolutionManagement block (4-space indent)
patch_file "$GRADLE_DIR/settings.gradle.kts" "        "
# ensure pluginManagement exists there too
if ! grep -q 'pluginManagement' "$GRADLE_DIR/settings.gradle.kts"; then
  cat > /tmp/pm.$$ <<EOF
pluginManagement {
    repositories {
        google()
        ${MIRROR}
        mavenCentral()
        gradlePluginPortal()
    }
}

$(cat "$GRADLE_DIR/settings.gradle.kts")
EOF
  mv /tmp/pm.$$ "$GRADLE_DIR/settings.gradle.kts"
  echo "added pluginManagement block to settings.gradle.kts"
fi
patch_file "$GRADLE_DIR/resolve_dependencies.gradle.kts" "    "

# example app settings (this repo)
EXAMPLE_SETTINGS="$(cd "$(dirname "$0")/../example/android" && pwd)/settings.gradle.kts"
if [ -f "$EXAMPLE_SETTINGS" ]; then
  patch_file "$EXAMPLE_SETTINGS" "        "
fi
