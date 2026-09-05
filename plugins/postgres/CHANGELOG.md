## 0.1.3

- Add dartdoc on internal API surfaces (10/10 pana dartdoc coverage).

## 0.1.2

- Add `PostgresBundleRow` + `mapRowToBundle` exports for writing custom server
  tooling on top of `flutter_ota_kit_postgres`.
- Repository moved to `https://github.com/HYPER12755/flutter-ota-kit`.

## 0.1.1

- Throw a clear `StateError` from `getDownloadUrl` when no `servingBaseUrl`
  is configured (previously the URL silently failed).
- Remove dead `IS NULL` filter paths in `_buildWhere`.

## 0.1.0

- Initial release of `flutter_ota_kit_postgres` as part of the flutter_ota_kit OTA toolkit.
