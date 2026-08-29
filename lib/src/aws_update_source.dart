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
import 'package:flutter_ota_kit_aws/flutter_ota_kit_aws.dart'
    show s3Database, s3Storage, S3DatabaseConfig, AwsS3StorageConfig;
import 'patch_info.dart' show PatchInfo;

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

final _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class AwsUpdateSource {
  AwsUpdateSource();

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
