import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show nilUuid, Platform, UpdateStrategy;
import 'package:flutter_ota_kit_client/flutter_ota_kit_client.dart'
    show ServerUpdateResult;
import 'package:flutter_ota_kit_postgres/flutter_ota_kit_postgres.dart'
    show postgresDatabase, postgresStorage, PostgresConfig, PostgresStorageConfig;
import 'shared_update_check.dart';

/// Configuration for a **Postgres** update source.
///
/// Like [SupabaseUpdateConfig], this talks to the backend directly — no separate
/// server process. The database plugin resolves the bundle metadata and the
/// storage plugin resolves the download URL. Because Postgres cannot serve bytes
/// over HTTP itself, [servingBaseUrl] must point at a proxy that reads from the
/// `flutter_ota_kit_storage` table (or leave it null and let the device read
/// directly if a PostgREST/HTTP layer is in front of the database).
class PostgresUpdateConfig {
  const PostgresUpdateConfig({
    required this.host,
    this.port = 5432,
    required this.database,
    this.username,
    this.password,
    this.sslMode,
    this.servingBaseUrl,
    required this.channel,
    required this.platform,
    required this.updateStrategy,
    this.appVersion,
    this.fingerprintHash,
    this.sdkVersion = '1.0.0',
    this.cohort,
    this.minBundleId = nilUuid,
  });

  final String host;
  final int port;
  final String database;
  final String? username;
  final String? password;
  final Object? sslMode;
  final String? servingBaseUrl;
  final String channel;
  final Platform platform;
  final UpdateStrategy updateStrategy;
  final String? appVersion;
  final String? fingerprintHash;
  final String sdkVersion;
  final String? cohort;
  final String minBundleId;
}

class PostgresUpdateSource {
  const PostgresUpdateSource();

  Future<ServerUpdateResult> check(
    PostgresUpdateConfig config, {
    String? currentBundleId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final dbConfig = PostgresConfig(
      host: config.host,
      port: config.port,
      database: config.database,
      username: config.username,
      password: config.password,
      sslMode: config.sslMode as dynamic,
    );
    final storageConfig = PostgresStorageConfig(
      db: dbConfig,
      servingBaseUrl: config.servingBaseUrl,
    );

    final db = postgresDatabase(dbConfig)();
    final storage = postgresStorage(storageConfig);

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
