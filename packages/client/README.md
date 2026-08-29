# flutter_ota_kit_client

The shared result type used by every flutter_ota_kit update check.

## What's inside

- `ServerUpdateResult` — the uniform object returned by every backend source
  (`SupabaseUpdateSource`, `PostgresUpdateSource`, `CloudflareUpdateSource`,
  `AwsUpdateSource`) so application code can treat all backends the same.

```dart
import 'package:flutter_ota_kit_client/flutter_ota_kit_client.dart';

final result = await FlutterPatcher.checkForUpdate();
if (result.hasUpdate) {
  await FlutterPatcher.applyUpdate(result);
}
```

`ServerUpdateResult` exposes `isUpToDate`, `hasUpdate`, `patch` (a `PatchInfo`),
`status` (`update` / `rollback` / `upToDate`), and `shouldForceUpdate` — a forced
update is applied and the app restarted automatically by `applyUpdate`.

## License

MIT.
