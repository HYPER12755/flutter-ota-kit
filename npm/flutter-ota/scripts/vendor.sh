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

echo "Done. dart-src size: $(du -sh "$DST" | cut -f1)"
