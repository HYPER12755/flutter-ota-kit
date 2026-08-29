# flutter_ota_kit_core

Pure-Dart core of the [flutter_ota_kit](https://github.com/HYPER12755/flutter_ota_kit) OTA toolkit. It has **no Flutter dependency** and is shared by every other package (client, plugin-core, and all four backends).

## What's inside

- **Data model** — `Bundle`, `PatchInfo`, `AppUpdateInfo`, and the `Platform` / `UpdateStrategy` / status enums that describe an over-the-air update.
- **Rollout math** — deterministic staged-rollout cohort helpers (`rollout.dart`).
- **Semver** — `semverSatisfies(target, range)` for matching a device's app version against a bundle's rollout rule.
- **Identifiers** — `uuidv7` generation plus a `NIL` sentinel (`uuid.dart`).
- **Bundle artifacts** — helpers to describe and address content-addressed patch artifacts.

## Usage

```dart
import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';

final ok = semverSatisfies('1.0.0', '>=1.0.0 <2.0.0'); // true
```

## License

MIT — see the [project LICENSE](https://github.com/HYPER12755/flutter_ota_kit/blob/main/LICENSE).
