#!/usr/bin/env bash
# Regenerate the vendored Dart source under dart-src/ from the monorepo so the
# npm package can `dart compile exe` on any architecture (e.g. arm64).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DST="$(cd "$(dirname "$0")/.." && pwd)/dart-src"
SRC="$ROOT"

echo "Vendoring Dart source from $SRC into $DST"

rm -rf "$DST"
mkdir -p "$DST/packages"

# Single-package layout (v0.2.0+): the former sub-packages (core, plugin-core,
# client, and the supabase/postgres/cloudflare/aws/pocketbase backends) now live
# INSIDE the root `flutter_ota_kit` package under lib/src/pkg/. So we only vendor
# the root package + the CLI. The CLI depends on the root via a path override.
#
# We copy the root package's publishable pieces (lib, android, pubspec, etc.)
# and the CLI. `example/` and build artifacts are dropped.
mkdir -p "$DST/root"
for item in lib android bin pubspec.yaml analysis_options.yaml LICENSE README.md; do
  [ -e "$SRC/$item" ] && cp -R "$SRC/$item" "$DST/root/$item"
done
cp -R "$SRC/packages/cli-tools" "$DST/packages/cli-tools"

# Repoint the CLI's `flutter_ota_kit` path override at the vendored root copy.
CLI_PUBSPEC="$DST/packages/cli-tools/pubspec.yaml"
if [ -f "$CLI_PUBSPEC" ]; then
  # dependency_overrides -> flutter_ota_kit -> path: ../.. becomes ../../root
  perl -0pi -e 's{(flutter_ota_kit:\s*\n\s*path:\s*)\.\.\/\.\.}{${1}../../root}g' "$CLI_PUBSPEC" 2>/dev/null || \
    sed -i 's|path: \.\./\.\.|path: ../../root|' "$CLI_PUBSPEC"
fi

# Drop tooling/lock artifacts so `dart pub get` resolves fresh on install.
find "$DST" -name pubspec.lock -delete
find "$DST" -name .dart_tool -type d -prune -exec rm -rf {} +
find "$DST" -name build -type d -prune -exec rm -rf {} +
find "$DST" -name .git -type d -prune -exec rm -rf {} +
find "$DST" -name coverage -type d -prune -exec rm -rf {} +

# Sync migration SQL files so the binary can find them at ../migrations/<backend>/.
# The SQL/DDL data still lives in the (non-Dart) plugins/* data dirs in the repo.
MIG_DST="$(cd "$(dirname "$0")/.." && pwd)/migrations"
rm -rf "$MIG_DST"

# Supabase: migrations live in plugins/supabase/supabase/migrations/
if [ -d "$SRC/plugins/supabase/supabase/migrations" ]; then
  mkdir -p "$MIG_DST/supabase"
  cp "$SRC/plugins/supabase/supabase/migrations"/*.sql "$MIG_DST/supabase/"
  echo "  synced migrations/supabase ($(ls "$MIG_DST/supabase/"*.sql | wc -l) files)"
fi

# Postgres: SQL lives in plugins/postgres/sql/
if [ -d "$SRC/plugins/postgres/sql" ]; then
  mkdir -p "$MIG_DST/postgres"
  cp "$SRC/plugins/postgres/sql"/*.sql "$MIG_DST/postgres/"
  echo "  synced migrations/postgres ($(ls "$MIG_DST/postgres/"*.sql | wc -l) files)"
fi

# Cloudflare: migrations live in plugins/cloudflare/migrations/
if [ -d "$SRC/plugins/cloudflare/migrations" ]; then
  mkdir -p "$MIG_DST/cloudflare"
  cp "$SRC/plugins/cloudflare/migrations"/*.sql "$MIG_DST/cloudflare/"
  echo "  synced migrations/cloudflare ($(ls "$MIG_DST/cloudflare/"*.sql | wc -l) files)"
fi

# AWS: migrations live in plugins/aws/migrations/ (if any)
if [ -d "$SRC/plugins/aws/migrations" ]; then
  mkdir -p "$MIG_DST/aws"
  cp "$SRC/plugins/aws/migrations"/*.sql "$MIG_DST/aws/"
  echo "  synced migrations/aws ($(ls "$MIG_DST/aws/"*.sql | wc -l) files)"
fi

echo "Done. dart-src size: $(du -sh "$DST" | cut -f1)"
