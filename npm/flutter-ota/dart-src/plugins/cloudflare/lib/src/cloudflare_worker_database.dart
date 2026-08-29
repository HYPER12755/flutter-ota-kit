import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show createDatabasePlugin;

import 'd1_client.dart' show D1ClientLike;
import 'd1_database_plugin.dart' show D1DatabasePlugin;

/// Configuration for the Cloudflare Workers D1 database plugin.
///
/// Mirrors hot-updater's `CloudflareWorkerDatabaseConfig`: instead of talking
/// to D1 over the REST API, the plugin uses a `D1Like` binding supplied by
/// [getDb] (the Workers runtime `env.DB`). In the Dart port the binding is
/// represented by a [D1ClientLike], which makes it trivially testable by
/// injecting a mock.
class CloudflareWorkerDatabaseConfig {
  const CloudflareWorkerDatabaseConfig({required this.getDb});

  final D1ClientLike Function() getDb;
}

/// Cloudflare Workers D1 database plugin (faithful port of hot-updater's
/// `cloudflareWorkerDatabase`).
///
/// Shares the exact same SQL/update-info logic as [d1Database]; only the
/// client source differs (an in-process D1 binding instead of the REST API).
final cloudflareWorkerDatabase =
    createDatabasePlugin<CloudflareWorkerDatabaseConfig>(
  name: 'd1WorkerDatabase',
  factory: (config) => D1DatabasePlugin(config.getDb()),
);
