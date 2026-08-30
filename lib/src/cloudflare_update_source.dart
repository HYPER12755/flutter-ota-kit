import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show nilUuid, Platform, UpdateStrategy;
import 'package:flutter_ota_kit_client/flutter_ota_kit_client.dart'
    show ServerUpdateResult;
import 'package:flutter_ota_kit_cloudflare/flutter_ota_kit_cloudflare.dart'
    show d1Database, r2Storage, D1DatabaseConfig, R2S3StorageConfig;
import 'shared_update_check.dart';

/// Configuration for a **Cloudflare** update source.
///
/// Talks to Cloudflare directly — D1 for bundle metadata and R2 (S3-compatible)
/// for artifact storage — with no intermediate server. Presigned R2 URLs are
/// resolved on the device, exactly like [SupabaseUpdateConfig].
class CloudflareUpdateConfig {
  const CloudflareUpdateConfig({
    // D1 (database)
    required this.databaseId,
    required this.accountId,
    required this.cloudflareApiToken,
    // R2 (storage)
    required this.bucketName,
    required this.accessKeyId,
    required this.secretAccessKey,
    this.basePath,
    this.region = 'auto',
    this.endpoint,
    // targeting
    required this.channel,
    required this.platform,
    required this.updateStrategy,
    this.appVersion,
    this.fingerprintHash,
    this.sdkVersion = '1.0.0',
    this.cohort,
    this.minBundleId = nilUuid,
  });

  final String databaseId;
  final String accountId;
  final String cloudflareApiToken;
  final String bucketName;
  final String accessKeyId;
  final String secretAccessKey;
  final String? basePath;
  final String region;
  final String? endpoint;
  final String channel;
  final Platform platform;
  final UpdateStrategy updateStrategy;
  final String? appVersion;
  final String? fingerprintHash;
  final String sdkVersion;
  final String? cohort;
  final String minBundleId;
}

class CloudflareUpdateSource {
  const CloudflareUpdateSource();

  Future<ServerUpdateResult> check(
    CloudflareUpdateConfig config, {
    String? currentBundleId,
  }) async {
    final dbConfig = D1DatabaseConfig(
      databaseId: config.databaseId,
      accountId: config.accountId,
      cloudflareApiToken: config.cloudflareApiToken,
    );
    final storageConfig = R2S3StorageConfig(
      accountId: config.accountId,
      bucketName: config.bucketName,
      accessKeyId: config.accessKeyId,
      secretAccessKey: config.secretAccessKey,
      basePath: config.basePath,
      region: config.region,
      endpoint: config.endpoint,
    );

    final db = d1Database(dbConfig)();
    final storage = r2Storage(storageConfig);

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
    );
  }
}
