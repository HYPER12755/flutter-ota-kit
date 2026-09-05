# flutter_ota_kit_pocketbase

PocketBase backend plugin for
[`flutter_ota_kit`](https://github.com/HYPER12755/flutter-ota-kit) — a
self-hostable code-push (OTA update) toolkit for Flutter Android.

PocketBase is a single-binary, Go-based backend that gives you SQLite,
auth, file storage, realtime, and an admin UI in one ~15 MB executable.
This plugin makes PocketBase a drop-in `DatabasePlugin` + `StoragePlugin`
for `flutter_ota_kit`.

## Install

```yaml
dependencies:
  flutter_ota_kit: ^0.1.10
  flutter_ota_kit_pocketbase: ^0.1.0
```

## Quick start

```dart
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'package:flutter_ota_kit_pocketbase/flutter_ota_kit_pocketbase.dart';

await FlutterPatcher.init(
  pocketbaseConfig: PocketBaseUpdateConfig(
    url: 'http://localhost:8090',
    adminEmail: 'admin@example.com',
    adminPassword: 'super-secret',
  ),
  // ... other FlutterPatcher options
);
```

## Start a local PocketBase with the schema pre-installed

```bash
flutter-ota serve -b pocketbase
```

This downloads PocketBase (if missing), creates the `bundles` and
`channels` collections, installs validation hooks, and starts the
admin UI at `http://localhost:8090/_/`.

## Documentation

- [Backend guide → PocketBase](https://github.com/HYPER12755/flutter-ota-kit/blob/main/doc/backends.md#pocketbase)
- [API reference](https://github.com/HYPER12755/flutter-ota-kit/blob/main/doc/api-reference.md)
- [Main README](https://github.com/HYPER12755/flutter-ota-kit)

## License

MIT — see [LICENSE](LICENSE).
