import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show nilUuid, Platform, UpdateStrategy;
import 'package:flutter_ota_kit_client/flutter_ota_kit_client.dart'
    show ServerUpdateResult;
import 'package:flutter_ota_kit_pocketbase/flutter_ota_kit_pocketbase.dart'
    show
        pocketbaseDatabase,
        pocketbaseStorage,
        PocketBaseConfig,
        PocketBaseStorageConfig;
import 'shared_update_check.dart';

/// Configuration for a **PocketBase** update source (self-hosted, single binary).
///
/// Talks to a PocketBase instance directly over its REST API. The schema must
/// be installed via `flutter_ota_kit pocketbase serve` (or the equivalent
/// admin script) before the first device check.
///
/// PocketBase is a single-binary Go backend (SQLite + auth + file storage +
/// realtime + admin UI in ~15MB). It's the recommended option for small teams
/// that want a Supabase-like experience without a cloud account.
class PocketBaseUpdateConfig {
  const PocketBaseUpdateConfig({
    required this.url,
    required this.adminEmail,
    required this.adminPassword,
    required this.bundlesCollection,
    required this.bundlesBucket,
    required this.channel,
    required this.platform,
    required this.updateStrategy,
    this.appVersion,
    this.fingerprintHash,
    this.sdkVersion = '1.0.0',
    this.cohort,
    this.minBundleId = nilUuid,
  });

  /// Base URL of the PocketBase instance, e.g. `https://pb.example.com`.
  final String url;

  /// Admin email (used to mint short-lived file tokens for downloads).
  final String adminEmail;

  /// Admin password.
  final String adminPassword;

  /// Name of the PB collection that stores bundle records.
  final String bundlesCollection;

  /// Name of the PB file storage bucket for bundle artifacts.
  final String bundlesBucket;

  final String channel;
  final Platform platform;
  final UpdateStrategy updateStrategy;
  final String? appVersion;
  final String? fingerprintHash;
  final String sdkVersion;
  final String? cohort;

  /// Build-time scan floor (mirrors hot-updater's `getMinBundleId()`). Bundles
  /// with an id older than this are never served.
  final String minBundleId;
}

/// Device-side update source backed by a self-hosted PocketBase instance.
class PocketBaseUpdateSource {
  const PocketBaseUpdateSource();

  Future<ServerUpdateResult> check(
    PocketBaseUpdateConfig config, {
    String? currentBundleId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final dbConfig = PocketBaseConfig(
      url: config.url,
      adminEmail: config.adminEmail,
      adminPassword: config.adminPassword,
      bundlesCollection: config.bundlesCollection,
    );
    final storageConfig = PocketBaseStorageConfig(
      url: config.url,
      adminEmail: config.adminEmail,
      adminPassword: config.adminPassword,
      bundlesCollection: config.bundlesCollection,
      bundlesBucket: config.bundlesBucket,
    );

    final db = pocketbaseDatabase(dbConfig)();
    final storage = pocketbaseStorage(storageConfig);

    return performSharedUpdateCheck(
      db: db,
      storage: storage,
      channel: config.channel,
      platform: config.platform,
      updateStrategy: config.updateStrategy,
      appVersion: config.appVersion,
      fingerprintHash: config.fingerprintHash,
      minBundleId: config.minBundleId,
      currentBundleId: currentBundleId,
      timeout: timeout,
    );
  }
}
