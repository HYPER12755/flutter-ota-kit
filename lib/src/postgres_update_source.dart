import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show
        AppUpdateStatus,
        AppVersionGetBundlesArgs,
        FingerprintGetBundlesArgs,
        GetBundlesArgs,
        nilUuid,
        Platform,
        UpdateInfo,
        UpdateStrategy;
import 'package:flutter_ota_kit_client/flutter_ota_kit_client.dart'
    show ServerUpdateResult;
import 'package:flutter_ota_kit_postgres/flutter_ota_kit_postgres.dart'
    show postgresDatabase, postgresStorage, PostgresConfig, PostgresStorageConfig;
import 'patch_info.dart' show PatchInfo;

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

final _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class PostgresUpdateSource {
  PostgresUpdateSource();

  Future<ServerUpdateResult> check(
    PostgresUpdateConfig config, {
    String? currentBundleId,
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

    final bundleId = (currentBundleId != null && _uuidRe.hasMatch(currentBundleId))
        ? currentBundleId
        : nilUuid;

    final GetBundlesArgs args;
    if (config.updateStrategy == UpdateStrategy.fingerprint) {
      args = FingerprintGetBundlesArgs(
        channel: config.channel,
        platform: config.platform,
        bundleId: bundleId,
        minBundleId: config.minBundleId,
        fingerprintHash: config.fingerprintHash ?? '',
      );
    } else {
      args = AppVersionGetBundlesArgs(
        channel: config.channel,
        platform: config.platform,
        bundleId: bundleId,
        minBundleId: config.minBundleId,
        appVersion: config.appVersion ?? '',
      );
    }

    final UpdateInfo? info = await db.getUpdateInfo(args);
    if (info == null) return ServerUpdateResult.upToDate();

    final storageUri = info.storageUri;
    if (storageUri == null || storageUri.isEmpty) {
      return ServerUpdateResult.upToDate();
    }

    final runtime = storage.profiles.runtime;
    if (runtime == null) return ServerUpdateResult.upToDate();
    final dl = await runtime.getDownloadUrl(storageUri);
    final fileUrl = dl['fileUrl'];
    if (fileUrl == null || fileUrl.isEmpty) {
      return ServerUpdateResult.upToDate();
    }

    final patch = PatchInfo(
      version: info.id,
      patchUrl: fileUrl,
      md5: info.fileHash ?? '',
    );
    return ServerUpdateResult(
      isUpToDate: false,
      patch: patch,
      status: AppUpdateStatus.update,
      shouldForceUpdate: info.shouldForceUpdate,
      id: info.id,
      message: info.message,
    );
  }
}
