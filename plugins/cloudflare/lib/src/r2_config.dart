import 'r2_s3_client.dart' show R2S3Client, R2S3ClientLike;

/// Configuration for the Cloudflare R2 S3-compatible storage plugin.
///
/// Mirrors hot-updater's `R2S3StorageConfig` (a thin wrapper over the AWS S3
/// client config). Credentials are passed directly (access/secret keys) and
/// the client signs requests with AWS Signature V4 against the R2 endpoint.
class R2S3StorageConfig {
  const R2S3StorageConfig({
    required this.accountId,
    required this.bucketName,
    required this.accessKeyId,
    required this.secretAccessKey,
    this.basePath,
    this.region = 'auto',
    this.endpoint,
    this.clientFactory,
  });

  /// Cloudflare account ID (used to build the R2 endpoint host).
  final String accountId;

  /// Target R2 bucket name.
  final String bucketName;

  /// S3 access key ID.
  final String accessKeyId;

  /// S3 secret access key.
  final String secretAccessKey;

  /// Optional base path prepended to all object keys.
  final String? basePath;

  /// R2 region (defaults to "auto").
  final String region;

  /// Override endpoint (defaults to `https://<accountId>.r2.cloudflarestorage.com`).
  final String? endpoint;

  /// Optional factory used to inject an [R2S3ClientLike] in tests.
  final R2S3ClientFactory? clientFactory;
}

/// Builds an [R2S3ClientLike] for the given [R2S3StorageConfig].
typedef R2S3ClientFactory = R2S3ClientLike Function(R2S3StorageConfig config);

/// Resolves the client for a config, using the injected factory when present.
R2S3ClientLike resolveR2Client(R2S3StorageConfig config) =>
    config.clientFactory?.call(config) ?? R2S3Client(config);
