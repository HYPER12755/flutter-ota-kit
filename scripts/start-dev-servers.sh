#!/usr/bin/env bash
# Dev servers for OTA testing of flutter_patcher.
#
#   bash scripts/start-dev-servers.sh
#
# Starts (idempotent, kills old instances first):
#   :3000  static file server serving the built APK (/app-release.apk)
#   :8080  flutter_patcher mock_server serving .ota/dist
#
# Both ports must be set to "Public" in the studio Ports panel so the
# device can reach them via https://<port>-<host>.
#
# All state lives in <repo>/.ota/ (persistent, gitignored).

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OTA="$REPO/.ota"
EXAMPLE="$REPO/example"
LOG_PREFIX="$OTA"

PY_CANDIDATES=(
  /nix/store/00x3abm7y8j13i6n4sahvbar99irkc7d-python3-3.11.14/bin/python3
  python3
  python
)
PY=""
for c in "${PY_CANDIDATES[@]}"; do
  if command -v "$c" >/dev/null 2>&1; then PY="$(command -v "$c")"; break; fi
done
if [ -z "$PY" ]; then echo "error: no python found" >&2; exit 1; fi

pkill -f '[h]ttp.server 3000' 2>/dev/null
pkill -f 'mock[_]server' 2>/dev/null
sleep 1

nohup "$PY" -m http.server 3000 --bind 0.0.0.0 -d "$OTA" \
  > "$LOG_PREFIX/fileserver.log" 2>&1 < /dev/null &
disown

cd "$EXAMPLE" || exit 1
nohup dart run flutter_patcher:mock_server \
  --dist "$OTA/dist" --port 8080 --host 0.0.0.0 \
  > "$LOG_PREFIX/mockserver.log" 2>&1 < /dev/null &
disown

sleep 5
curl -s -r 0-15 -o /dev/null -w "apk server (3000): HTTP %{http_code}\n" \
  http://localhost:3000/app-release.apk
curl -s -m 5 http://localhost:8080/check && echo
