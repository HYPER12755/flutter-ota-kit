# flutter_ota_kit example

The smallest end-to-end asset-replacement demo. The screen renders
`Image.asset('assets/patch_demo.png')`; the bundled patch swaps the image
under the same asset key on the next cold start.

## Run

```bash
flutter build apk --debug
flutter install
```

Tap **Apply patch** → force-stop → reopen → image changes.
Tap **Rollback** → cold-start → image reverts to the APK version.

For `--assets` usage, the `patch.zip` layout, and other pack CLI flags, see
[API Reference → Asset Patching](../doc/api-reference.md#asset-patching).
The bundled `assets/asset_patch_preload.zip` was produced by the same flow.

## HTTP flow against a cloud backend

For a real over-HTTP flow, build a patched APK, pack it, and deploy to a cloud
backend such as Supabase:

```bash
dart run flutter_ota_kit:pack \
  --apk path/to/patched-app-release.apk \
  --version dev-asset-1 \
  --target-version-code 1 \
  --assets assets/patch_demo.png

flutter-ota deploy --source dist \
  --channel production --backend supabase \
  --key <PRIVATE_KEY_BASE64>
```

The app is then configured with `FlutterPatcher.configureSupabase(...)` and pulls
updates from the backend.

## Configuration (config file OR `.env`, both supported)

The example is wired by the generated `lib/flutter_ota_kit_setup.dart`
(produced by `flutter-ota init`). Every configurable value is resolved from:

1. build-time environment (`--dart-define`, e.g. `--dart-define-from-file=example/.env`)
2. the project config written by `init` under `.flutter_ota_kit/` (git-ignored)
3. built-in defaults

Environment wins. So secrets live only in `.env` and are never committed; the
config file and `lib/flutter_ota_kit_setup.dart` hold only non-secret defaults.

```bash
cp example/.env.example example/.env   # then fill in your project URL + anon key
flutter run --dart-define-from-file=example/.env
# or build a release APK for device/E2E:
flutter build apk --release --target-platform android-x64 \
  --dart-define-from-file=example/.env
```

`example/.env` is gitignored; only `example/.env.example` (placeholders) is
committed. Without credentials the bundled asset-patch demo still runs, but the
over-HTTP update flow is skipped.
