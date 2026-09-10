#!/usr/bin/env bash
# Smart publish script for flutter_ota_kit monorepo.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DART="/home/user/flutter/bin/dart"
DRY_RUN=false

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

# Safety: abort on uncommitted changes (except dry-run)
if [[ "$DRY_RUN" != true ]]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    error "Uncommitted changes detected. Commit or stash first."
    git status --short
    exit 1
  fi
fi

# Cleanup handler for SIGINT/SIGTERM/EXIT
cleanup() {
  local exit_code=$?
  for p in "${PACKAGES[@]}" "."; do
    [[ -f "$ROOT/$p/pubspec.yaml.bak" ]] && mv -f "$ROOT/$p/pubspec.yaml.bak" "$ROOT/$p/pubspec.yaml"
  done
  [[ -f "$ROOT/.pubignore.bak" ]] && mv -f "$ROOT/.pubignore.bak" "$ROOT/.pubignore"
  exit $exit_code
}
trap cleanup EXIT INT TERM

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

update_dep_constraint() {
  local file="$1"
  local dep="$2"
  local new_ver="$3"
  sed -i -E "s/^([[:space:]]*${dep}:[[:space:]]*)[^#]*/\1^${new_ver}/" "$file"
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  flutter_ota_kit - Smart Publish"
[[ "$DRY_RUN" == true ]] && echo "  (DRY RUN MODE)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Collect local versions
declare -A LOCAL_VER PUB_VER TARGET_VER
for p in "${PACKAGES[@]}"; do
  LOCAL_VER["$p"]=$(get_local_version "$ROOT/$p")
done
LOCAL_VER["."]=$(get_local_version "$ROOT")

# Check published and determine target versions
log "Checking published versions on pub.dev..."
for p in "${PACKAGES[@]}"; do
  name="${PKG_NAME[$p]}"
  pub=$(get_published_version "$name")
  PUB_VER["$p"]="$pub"
  local="${LOCAL_VER[$p]}"
  
  if [[ -z "$pub" ]]; then
    TARGET_VER["$p"]="$local"
    log "$name: not published, using local $local"
  elif [[ "$local" == "$pub" ]]; then
    TARGET_VER["$p"]="$local"
    log "$name: local == published ($local), skipping"
  elif version_ge "$local" "$pub"; then
    TARGET_VER["$p"]=$(bump_patch "$local")
    log "$name: local ($local) > published ($pub), bumping to ${TARGET_VER[$p]}"
  else
    TARGET_VER["$p"]=$(bump_patch "$pub")
    log "$name: local ($local) < published ($pub), bumping to ${TARGET_VER[$p]}"
  fi
done

# Root package
root_local="${LOCAL_VER[.]}"
root_pub=$(get_published_version "flutter_ota_kit")
PUB_VER["."]="$root_pub"
if [[ -z "$root_pub" ]]; then
  TARGET_VER["."]="$root_local"
elif [[ "$root_local" == "$root_pub" ]]; then
  TARGET_VER["."]="$root_local"
  log "flutter_ota_kit (root): local == published ($root_local), skipping"
elif version_ge "$root_local" "$root_pub"; then
  TARGET_VER["."]=$(bump_patch "$root_local")
  log "flutter_ota_kit (root): local > published, bumping to ${TARGET_VER[.]}"
else
  TARGET_VER["."]=$(bump_patch "$root_pub")
  log "flutter_ota_kit (root): local < published, bumping to ${TARGET_VER[.]}"
fi

# Update local pubspec versions + CHANGELOG (skip CHANGELOG in dry-run)
for p in "${PACKAGES[@]}" "."; do
  target="${TARGET_VER[$p]}"
  local="${LOCAL_VER[$p]}"
  if [[ "$target" != "$local" ]]; then
    log "Updating $p version: $local -> $target"
    if [[ "$DRY_RUN" != true ]]; then
      sed -i "s/^version: $local$/version: $target/" "$ROOT/$p/pubspec.yaml"
      today=$(date +%Y-%m-%d)
      tmp=$(mktemp)
      { echo "## $target"; echo; echo "- Release $today"; echo; cat "$ROOT/$p/CHANGELOG.md"; } > "$tmp"
      mv "$tmp" "$ROOT/$p/CHANGELOG.md"
    fi
  else
    log "$p: version unchanged ($local)"
  fi
done

# Update version constraints in dependent packages
log "Updating version constraints in dependent packages..."

update_dep_constraint() {
  local file="$1"
  local dep="$2"
  local new_ver="$3"
  sed -i -E "s/^([[:space:]]*${dep}:[[:space:]]*)[^#]*/\1^${new_ver}/" "$file"
}

update_dep_constraint "$ROOT/plugins/plugin-core/pubspec.yaml" "flutter_ota_kit_core" "${TARGET_VER[packages/core]}"
update_dep_constraint "$ROOT/packages/client/pubspec.yaml" "flutter_ota_kit_core" "${TARGET_VER[packages/core]}"
update_dep_constraint "$ROOT/packages/client/pubspec.yaml" "flutter_ota_kit_plugin_core" "${TARGET_VER[plugins/plugin-core]}"

for p in plugins/aws plugins/cloudflare plugins/postgres plugins/supabase plugins/pocketbase; do
  update_dep_constraint "$ROOT/$p/pubspec.yaml" "flutter_ota_kit_core" "${TARGET_VER[packages/core]}"
  update_dep_constraint "$ROOT/$p/pubspec.yaml" "flutter_ota_kit_plugin_core" "${TARGET_VER[plugins/plugin-core]}"
done

for p in "${PACKAGES[@]}"; do
  name="${PKG_NAME[$p]}"
  update_dep_constraint "$ROOT/pubspec.yaml" "$name" "${TARGET_VER[$p]}"
done

if [[ "$DRY_RUN" == true ]]; then
  warn "DRY RUN: Would publish all packages with updated constraints"
  echo
  echo "Target versions:"
  for p in "${PACKAGES[@]}" "."; do
    echo "  ${PKG_NAME[$p]:-${p}}: ${TARGET_VER[$p]}"
  done
  exit 0
fi

# Publish in dependency order
for p in "${PACKAGES[@]}"; do
  name="${PKG_NAME[$p]}"
  target="${TARGET_VER[$p]}"
  
  # Skip if already published at target
  current_pub=$(get_published_version "$name")
  if [[ "$current_pub" == "$target" ]]; then
    log "$name@$target already published, skipping"
    continue
  fi

  echo
  echo "━━━ Publishing $name@$target ━━━"

  cp "$ROOT/$p/pubspec.yaml" "$ROOT/$p/pubspec.yaml.bak"
  pubignore="$ROOT/.pubignore"
  backup="$ROOT/.pubignore.bak"
  [[ -f "$pubignore" ]] && mv "$pubignore" "$backup"

  [[ ! -f "$ROOT/$p/LICENSE" ]] && cp "$ROOT/LICENSE" "$ROOT/$p/LICENSE" 2>/dev/null || true

  if grep -q "dependency_overrides:" "$ROOT/$p/pubspec.yaml"; then
    sed -i '/^dependency_overrides:/,/^[a-z]/ {/^[a-z]/!d;}' "$ROOT/$p/pubspec.yaml"
  fi

  if (cd "$ROOT/$p" && "$DART" pub publish --force); then
    success "Published $name@$target"
  else
    error "Failed to publish $name"
    exit 1
  fi

  mv "$ROOT/$p/pubspec.yaml.bak" "$ROOT/$p/pubspec.yaml"
  [[ -f "$backup" ]] && mv "$backup" "$pubignore"
done

# Publish root
root_target="${TARGET_VER[.]}"
current_root_pub=$(get_published_version "flutter_ota_kit")
if [[ "$current_root_pub" == "$root_target" ]]; then
  log "flutter_ota_kit@$root_target already published, skipping"
else
  echo
  echo "━━━ Publishing flutter_ota_kit@$root_target ━━━"

  cp "$ROOT/pubspec.yaml" "$ROOT/pubspec.yaml.bak"
  pubignore="$ROOT/.pubignore"
  backup="$ROOT/.pubignore.bak"
  [[ -f "$pubignore" ]] && mv "$pubignore" "$backup"

  if grep -q "dependency_overrides:" "$ROOT/pubspec.yaml"; then
    sed -i '/^dependency_overrides:/,/^[a-z]/ {/^[a-z]/!d;}' "$ROOT/pubspec.yaml"
  fi

  if (cd "$ROOT" && "$DART" pub publish --force); then
    success "Published flutter_ota_kit@$root_target"
  else
    error "Failed to publish root"
    exit 1
  fi

  mv "$ROOT/pubspec.yaml.bak" "$ROOT/pubspec.yaml"
  [[ -f "$backup" ]] && mv "$backup" "$pubignore"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
success "All packages published successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
