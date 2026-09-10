#!/usr/bin/env bash
# Version bump script: calculates next versions, updates all pubspecs + constraints.
# Does NOT publish. Run manually with `dart pub publish -C <dir> --force` after.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Package dependency order (leaf to root)
PACKAGES=(
  "packages/core"
  "plugins/plugin-core"
  "packages/client"
  "plugins/aws"
  "plugins/cloudflare"
  "plugins/postgres"
  "plugins/supabase"
  "plugins/pocketbase"
)

declare -A PKG_NAME
for p in "${PACKAGES[@]}"; do
  PKG_NAME["$p"]=$(grep '^name:' "$ROOT/$p/pubspec.yaml" | awk '{print $2}')
done

get_local_version() {
  grep '^version:' "$1/pubspec.yaml" | awk '{print $2}'
}

get_published_version() {
  curl -s "https://pub.dev/api/packages/$1" 2>/dev/null | grep -o '"version":"[^"]*"' | head -1 | sed 's/"version":"//;s/"//'
}

bump_patch() {
  local ver="$1"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$ver"
  echo "$major.$minor.$((patch + 1))"
}

version_ge() {
  local v1="$1" v2="$2"
  [[ "$v1" == "$v2" ]] && return 0
  local IFS=.
  local v1a=($v1) v2a=($v2)
  for i in 0 1 2; do
    (( ${v1a[i]:-0} > ${v2a[i]:-0} )) && return 0
    (( ${v1a[i]:-0} < ${v2a[i]:-0} )) && return 1
  done
  return 0
}

echo "=== Calculating version bumps ==="

declare -A LOCAL_VER PUB_VER TARGET_VER
for p in "${PACKAGES[@]}"; do
  LOCAL_VER["$p"]=$(get_local_version "$ROOT/$p")
done
LOCAL_VER["."]=$(get_local_version "$ROOT")

# Check published and determine target
for p in "${PACKAGES[@]}"; do
  name="${PKG_NAME[$p]}"
  pub=$(get_published_version "$name")
  local="${LOCAL_VER[$p]}"
  
  if [[ -z "$pub" ]]; then
    TARGET_VER["$p"]="$local"
    echo "  $name: not published, keep $local"
  elif [[ "$local" == "$pub" ]]; then
    TARGET_VER["$p"]="$local"
    echo "  $name: in sync ($local)"
  elif version_ge "$local" "$pub"; then
    TARGET_VER["$p"]=$(bump_patch "$local")
    echo "  $name: local > published, bump to ${TARGET_VER[$p]}"
  else
    TARGET_VER["$p"]=$(bump_patch "$pub")
    echo "  $name: local < published, bump to ${TARGET_VER[$p]}"
  fi
done

# Root
root_local="${LOCAL_VER[.]}"
root_pub=$(get_published_version "flutter_ota_kit")
if [[ -z "$root_pub" ]]; then
  TARGET_VER["."]="$root_local"
elif [[ "$root_local" == "$root_pub" ]]; then
  TARGET_VER["."]="$root_local"
elif version_ge "$root_local" "$root_pub"; then
  TARGET_VER["."]=$(bump_patch "$root_local")
else
  TARGET_VER["."]=$(bump_patch "$root_pub")
fi
echo "  flutter_ota_kit: $root_local vs $root_pub -> ${TARGET_VER[.]}"

# Apply version bumps to pubspec.yaml + CHANGELOG
echo
echo "=== Applying version bumps ==="
for p in "${PACKAGES[@]}" "."; do
  target="${TARGET_VER[$p]}"
  local="${LOCAL_VER[$p]}"
  if [[ "$target" != "$local" ]]; then
    echo "  $p: $local -> $target"
    sed -i "s/^version: $local$/version: $target/" "$ROOT/$p/pubspec.yaml"
    today=$(date +%Y-%m-%d)
    tmp=$(mktemp)
    { echo "## $target"; echo; echo "- Release $today"; echo; cat "$ROOT/$p/CHANGELOG.md"; } > "$tmp"
    mv "$tmp" "$ROOT/$p/CHANGELOG.md"
  else
    echo "  $p: unchanged ($local)"
  fi
done

# Update version constraints in dependent pubspecs
echo
echo "=== Updating version constraints ==="

update_dep() {
  local file="$1" dep="$2" ver="$3"
  sed -i -E "s/^([[:space:]]*${dep}:[[:space:]]*)[^#]*/\1^${ver}/" "$file"
  echo "  $file: $dep -> ^$ver"
}

update_dep "$ROOT/plugins/plugin-core/pubspec.yaml" "flutter_ota_kit_core" "${TARGET_VER[packages/core]}"
update_dep "$ROOT/packages/client/pubspec.yaml" "flutter_ota_kit_core" "${TARGET_VER[packages/core]}"
update_dep "$ROOT/packages/client/pubspec.yaml" "flutter_ota_kit_plugin_core" "${TARGET_VER[plugins/plugin-core]}"

for p in plugins/aws plugins/cloudflare plugins/postgres plugins/supabase plugins/pocketbase; do
  update_dep "$ROOT/$p/pubspec.yaml" "flutter_ota_kit_core" "${TARGET_VER[packages/core]}"
  update_dep "$ROOT/$p/pubspec.yaml" "flutter_ota_kit_plugin_core" "${TARGET_VER[plugins/plugin-core]}"
done

for p in "${PACKAGES[@]}"; do
  name="${PKG_NAME[$p]}"
  update_dep "$ROOT/pubspec.yaml" "$name" "${TARGET_VER[$p]}"
done

echo
echo "=== Done ==="
echo "Next: run 'dart pub publish -C <dir> --force' for each package in order:"
for p in "${PACKAGES[@]}" "."; do
  echo "  dart pub publish -C $p --force"
done
