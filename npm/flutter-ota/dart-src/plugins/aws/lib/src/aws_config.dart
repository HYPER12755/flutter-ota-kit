import 'dart:io' show Platform;

import 'aws_s3_client.dart' show AwsS3Client, AwsS3ClientLike;

/// Configuration for the AWS S3 storage plugin.
///
/// Faithful port of hot-updater `S3StorageConfig` (extends the AWS SDK
/// `S3ClientConfig` with `bucketName` and `basePath`).
class AwsS3StorageConfig {
  AwsS3StorageConfig({
    required this.bucketName,
    required this.region,
    required this.accessKeyId,
    required this.secretAccessKey,
    this.basePath,
    this.endpoint,
    this.sessionToken,
    this.clientFactory = defaultAwsS3ClientFactory,
  });

  final String bucketName;
  final String region;
  final String accessKeyId;
  final String secretAccessKey;
  final String? basePath;
  final String? endpoint;
  final String? sessionToken;

  /// Test seam: override the concrete S3 client.
  final AwsS3ClientLike Function(AwsS3StorageConfig config) clientFactory;
}

/// Default factory producing a real [AwsS3Client] with runtime region applied.
AwsS3ClientLike defaultAwsS3ClientFactory(AwsS3StorageConfig config) =>
    AwsS3Client(applyS3RuntimeAwsConfig(config));

/// Fill in a default region from the environment when one is not supplied
/// (mirrors hot-updater's `applyS3RuntimeAwsConfig`).
AwsS3StorageConfig applyS3RuntimeAwsConfig(AwsS3StorageConfig config) {
  if (config.region.isNotEmpty) return config;
  final envRegion =
      Platform.environment['AWS_REGION'] ??
      Platform.environment['AWS_DEFAULT_REGION'];
  if (envRegion == null || envRegion.isEmpty) return config;
  return AwsS3StorageConfig(
    bucketName: config.bucketName,
    region: envRegion,
    accessKeyId: config.accessKeyId,
    secretAccessKey: config.secretAccessKey,
    basePath: config.basePath,
    endpoint: config.endpoint,
    sessionToken: config.sessionToken,
    clientFactory: config.clientFactory,
  );
}

/// Resolve the concrete S3 client from config (seam for tests).
AwsS3ClientLike resolveAwsS3Client(AwsS3StorageConfig config) =>
    config.clientFactory(config);
