/// flutter_ota_kit_postgres — Postgres backend plugin for flutter_ota_kit.
///
/// Faithful port of hot-updater `plugins/postgres`.
library;

export 'src/postgres_config.dart'
    show PostgresConfig, PostgresClientFactory;
export 'src/postgres_client.dart'
    show PostgresClientLike, PostgresClient;
export 'src/postgres_database.dart' show postgresDatabase;
export 'src/postgres_storage.dart'
    show postgresStorage, PostgresStorageConfig, resolvePostgresStorageClient;
export 'src/postgres_get_update_info.dart' show getUpdateInfo;
export 'src/postgres_types.dart'
    show PostgresBundleRow, PostgresBundlePatchRow;
export 'src/postgres_bundle_mapper.dart'
    show mapRowToBundle, bundleToRowValues, bundleToPatchRows;
