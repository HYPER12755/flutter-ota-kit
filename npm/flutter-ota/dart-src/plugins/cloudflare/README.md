# flutter_ota_kit_cloudflare

Cloudflare backend for flutter_ota_kit: bundle metadata in **D1** (SQLite-at-edge)
and artifacts in **R2** (S3-compatible storage). Used by the `flutter-ota` CLI and
the Flutter SDK's `FlutterPatcher.configureCloudflare(...)`.

## What's inside

- `d1Database` / `D1DatabaseConfig` — bundle metadata in D1.
  `CloudflareWorkerDatabaseConfig` / `cloudflareWorkerDatabase` for the
  Worker-facing variant.
- `r2Storage` / `R2S3StorageConfig` — artifact storage in R2 (AWS SigV4).
- D1 row mappers and `D1ClientFactory` / `R2S3ClientFactory` test seams.

## Configuration (environment)

| Variable | Purpose |
| --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account id. |
| `CLOUDFLARE_API_TOKEN` | API token with D1 read/write + R2 permissions. |
| R2 access/secret keys + bucket | Supplied via `R2S3StorageConfig` (see the CLI `init` and `doc/backends.md`). |

## License

MIT.
