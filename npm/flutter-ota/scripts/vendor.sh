#!/usr/bin/env bash
# Regenerate the vendored Dart source under dart-src/ from the monorepo so the
# npm package can `dart compile exe` on any architecture (e.g. arm64).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DST="$(cd "$(dirname "$0")/.." && pwd)/dart-src"
SRC="$ROOT"

echo "Vendoring Dart source from $SRC into $DST"

rm -rf "$DST"
mkdir -p "$DST/packages" "$DST/plugins"

for p in packages/core packages/cli-tools; do
  cp -R "$SRC/$p" "$DST/$p"
done
for p in plugins/cloudflare plugins/plugin-core plugins/postgres plugins/aws plugins/supabase plugins/pocketbase; do
  cp -R "$SRC/$p" "$DST/$p"
done

# Drop tooling/lock artifacts so `dart pub get` resolves fresh on install.
find "$DST" -name pubspec.lock -delete
find "$DST" -name .dart_tool -type d -prune -exec rm -rf {} +
find "$DST" -name build -type d -prune -exec rm -rf {} +
find "$DST" -name .git -type d -prune -exec rm -rf {} +
find "$DST" -name coverage -type d -prune -exec rm -rf {} +

# Sync migration SQL files so the binary can find them at ../migrations/<backend>/
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
