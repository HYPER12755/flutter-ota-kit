# flutter_ota_kit_postgres

Postgres backend for flutter_ota_kit: bundle metadata in a Postgres database and
artifacts in the bytea-backed storage plugin. Used by the `flutter-ota` CLI and
the Flutter SDK's `FlutterPatcher.configurePostgres(...)`.

## What's inside

- `postgresDatabase` / `PostgresConfig` — bundle read/write over a Postgres
  connection.
- `postgresStorage` / `PostgresStorageConfig` / `resolvePostgresStorageClient` —
  artifact storage.
- `getUpdateInfo` — resolve the latest applicable bundle for a device.
- Row mappers (`PostgresBundleRow`, `PostgresBundlePatchRow`,
  `bundleToRowValues`, `bundleToPatchRows`) for the `bundles` / `bundle_patches`
  tables.

## Configuration (environment)

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | Full Postgres connection string (preferred). |
| `POSTGRES_HOST` / `POSTGRES_PORT` / `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_SSLMODE` | Individual connection fields. |
| `POSTGRES_SERVING_BASE_URL` | HTTP proxy/base URL in front of the storage table for artifact downloads. |
| `POSTGRES_BASE_PATH` | Optional object-key prefix. |

## License

MIT.
