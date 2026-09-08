#!/usr/bin/env bash
# Publish all pub.dev packages from the monorepo root.
# Usage: ./scripts/publish-packages.sh [package-name]
#   No args  → publish all 8 packages in dependency order
#   With arg → publish only the named package

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Packages in dependency order (core first, then plugin-core, then the rest).
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

publish_one() {
  local dir="$ROOT/$1"
  local name
  name=$(grep '^name:' "$dir/pubspec.yaml" | awk '{print $2}')
  local ver
  ver=$(grep '^version:' "$dir/pubspec.yaml" | awk '{print $2}')

  echo ""
  echo "━━━ Publishing $name@$ver ━━━"

  # Temporarily move .pubignore aside so pub can see the pubspec.
  local pubignore="$ROOT/.pubignore"
  local backup="$ROOT/.pubignore.bak"
  if [ -f "$pubignore" ]; then
    mv "$pubignore" "$backup"
  fi

  # Also ensure LICENSE exists.
  if [ ! -f "$dir/LICENSE" ]; then
    cp "$ROOT/LICENSE" "$dir/LICENSE" 2>/dev/null || true
  fi

  (cd "$dir" && /tmp/flutter/bin/cache/dart-sdk/bin/dart pub publish --force)

  # Restore .pubignore.
  if [ -f "$backup" ]; then
    mv "$backup" "$pubignore"
  fi

  echo "✓ $name@$ver published"
}

if [ "${1:-}" != "" ]; then
  # Find the package dir by name.
  found=""
  for pkg in "${PACKAGES[@]}"; do
    pkg_name=$(grep '^name:' "$ROOT/$pkg/pubspec.yaml" | awk '{print $2}')
    if [ "$pkg_name" = "$1" ]; then
      found="$pkg"
      break
    fi
  done
  if [ -z "$found" ]; then
    echo "Package '$1' not found. Available:"
    for pkg in "${PACKAGES[@]}"; do
      grep '^name:' "$ROOT/$pkg/pubspec.yaml" | awk '{printf "  %s\n", $2}'
    done
    exit 1
  fi
  publish_one "$found"
else
  for pkg in "${PACKAGES[@]}"; do
    publish_one "$pkg"
  done
fi

echo ""
echo "All done."
