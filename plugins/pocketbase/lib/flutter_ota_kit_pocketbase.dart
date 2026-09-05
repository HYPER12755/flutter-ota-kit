/// flutter_ota_kit_pocketbase — PocketBase backend for flutter_ota_kit.
///
/// PocketBase is a single-binary, self-hostable backend (similar to Supabase)
/// that gives you SQLite, auth, file storage, realtime, and an admin UI in
/// one ~15MB Go binary. This plugin makes it a drop-in `DatabasePlugin` +
/// `StoragePlugin` for flutter_ota_kit.
///
/// Pair this with `flutter_ota_kit serve` (cli-tools) to start a local
/// PocketBase instance with the flutter_ota_kit schema pre-installed, plus
/// an admin UI at `http://localhost:8090/_/`.
library;

export 'src/pocketbase_config.dart';
export 'src/pocketbase_client.dart'
    show
        PocketBaseClient,
        PocketBaseClientFactory,
        PocketBaseException,
        PocketBaseList;
export 'src/pocketbase_database.dart'
    show pocketbaseDatabase, PocketBaseDatabaseConfig;
export 'src/pocketbase_storage.dart'
    show
        pocketbaseStorage,
        PocketBaseStorageConfig,
        parsePocketBaseStorageUri,
        buildPocketBaseStorageUri;
export 'src/pocketbase_bundle_mapper.dart';
