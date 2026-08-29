# flutter_ota_kit_plugin_core

Internal plugin abstractions shared by the flutter_ota_kit backend plugins
(`flutter_ota_kit_supabase`, `flutter_ota_kit_postgres`,
`flutter_ota_kit_cloudflare`, `flutter_ota_kit_aws`).

## What's inside

- The `Database`, `Storage`, and build interfaces that each backend implements.
- Factory helpers: `createDatabasePlugin`, `createStoragePlugin`,
  `createBlobDatabasePlugin`.
- Pagination, content-addressed asset addressing, and storage/bundle layout
  helpers used to keep all backends wire-compatible with the same bundle schema.

This package is a building block for the concrete backends and the `flutter-ota`
CLI; application code normally consumes the higher-level `flutter_ota_kit` API
instead.

## License

MIT.
