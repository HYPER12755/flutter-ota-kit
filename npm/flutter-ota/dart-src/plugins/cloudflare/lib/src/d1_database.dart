import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show createDatabasePlugin;

import 'd1_config.dart' show D1DatabaseConfig, resolveD1Client;
import 'd1_database_plugin.dart' show D1DatabasePlugin;

/// Cloudflare D1 database plugin over the REST API (faithful port of
/// hot-updater's `d1Database`).
///
/// Issues raw SQLite statements against Cloudflare D1 over the REST API and
/// resolves update information in-process via [resolveUpdateInfoFromBundles]
/// (no SQL stored procedures, unlike the Supabase/Postgres backends).
final d1Database = createDatabasePlugin<D1DatabaseConfig>(
  name: 'd1Database',
  factory: (config) => D1DatabasePlugin(resolveD1Client(config)),
);
