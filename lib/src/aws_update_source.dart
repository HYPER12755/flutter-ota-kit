import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show nilUuid, Platform, UpdateStrategy;
import 'package:flutter_ota_kit_client/flutter_ota_kit_client.dart'
    show ServerUpdateResult;
import 'package:flutter_ota_kit_aws/flutter_ota_kit_aws.dart'
    show s3Database, s3Storage, S3DatabaseConfig, AwsS3StorageConfig;
import 'shared_update_check.dart';

/// Configuration for an **AWS S3** update source.
///
/// Talks to AWS directly — an S3-backed blob database for bundle metadata and
/// S3 (presigned URLs) for artifact storage — with no intermediate server.
/// Optionally fronts downloads with CloudFront for a custom domain.
class AwsUpdateConfig {
  const AwsUpdateConfig({
    required this.bucketName,
    required this.region,
    required this.accessKeyId,
    required this.secretAccessKey,
    this.basePath,
    this.endpoint,
    this.sessionToken,
    this.cloudfrontDistributionId,
    required this.channel,
    required this.platform,
    required this.updateStrategy,
    this.appVersion,
    this.fingerprintHash,
    this.sdkVersion = '1.0.0',
    this.cohort,
    this.minBundleId = nilUuid,
  });

  final String bucketName;
  final String region;
  final String accessKeyId;
  final String secretAccessKey;
  final String? basePath;
  final String? endpoint;
  final String? sessionToken;
  final String? cloudfrontDistributionId;
  final String channel;
  final Platform platform;
  final UpdateStrategy updateStrategy;
  final String? appVersion;
  final String? fingerprintHash;
  final String sdkVersion;
  final String? cohort;
  final String minBundleId;
}

class AwsUpdateSource {
  const AwsUpdateSource();

  Future<ServerUpdateResult> check(
    AwsUpdateConfig config, {
    String? currentBundleId,
  }) async {
    final dbConfig = S3DatabaseConfig(
      bucketName: config.bucketName,
      region: config.region,
      accessKeyId: config.accessKeyId,
      secretAccessKey: config.secretAccessKey,
      basePath: config.basePath,
      cloudfrontDistributionId: config.cloudfrontDistributionId,
      endpoint: config.endpoint,
      sessionToken: config.sessionToken,
    );
    final storageConfig = AwsS3StorageConfig(
      bucketName: config.bucketName,
      region: config.region,
      accessKeyId: config.accessKeyId,
      secretAccessKey: config.secretAccessKey,
      basePath: config.basePath,
      endpoint: config.endpoint,
      sessionToken: config.sessionToken,
    );

    final db = s3Database(dbConfig)();
    final storage = s3Storage(storageConfig);

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
