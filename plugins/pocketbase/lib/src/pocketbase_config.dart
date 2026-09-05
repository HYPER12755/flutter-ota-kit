/// Configuration for the PocketBase backend plugin.
library;

import 'pocketbase_client.dart';

/// Configuration for the PocketBase database plugin.
///
/// This is a standalone config (does not import flutter_ota_kit_cli) so the
/// plugin can be reused in any Dart application. The CLI's `resolvePocketBaseConfig`
/// helper in `cli-tools` converts a `FlutterPatcherConfig` + env vars into this.
class PocketBaseConfig {
  const PocketBaseConfig({
    required this.url,
    required this.adminEmail,
    required this.adminPassword,
    this.bundlesCollection = 'bundles',
    this.channelsCollection = 'channels',
    this.bundlesBucket = 'bundles',
    this.clientFactory,
  });

  /// Base URL of the PocketBase instance, e.g. `http://localhost:8090`.
  final String url;

  /// Admin email (used to mint auth tokens for backend operations).
  final String adminEmail;

  /// Admin password.
  final String adminPassword;

  /// Name of the PB collection that stores bundle records.
  final String bundlesCollection;

  /// Name of the PB collection that stores channels.
  final String channelsCollection;

  /// Name of the PB file storage bucket for bundle artifacts.
  final String bundlesBucket;

  /// Optional test seam: a factory that builds the [PocketBaseClient] used by
  /// the plugin. When omitted, a default HTTP-backed client is created.
  final PocketBaseClientFactory? clientFactory;

  PocketBaseConfig copyWith({
    String? url,
    String? adminEmail,
    String? adminPassword,
    String? bundlesCollection,
    String? channelsCollection,
    String? bundlesBucket,
    PocketBaseClientFactory? clientFactory,
  }) =>
      PocketBaseConfig(
        url: url ?? this.url,
        adminEmail: adminEmail ?? this.adminEmail,
        adminPassword: adminPassword ?? this.adminPassword,
        bundlesCollection: bundlesCollection ?? this.bundlesCollection,
        channelsCollection: channelsCollection ?? this.channelsCollection,
        bundlesBucket: bundlesBucket ?? this.bundlesBucket,
        clientFactory: clientFactory ?? this.clientFactory,
      );
}
