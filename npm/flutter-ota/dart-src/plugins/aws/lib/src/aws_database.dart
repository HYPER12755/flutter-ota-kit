import 'dart:convert' show jsonDecode, jsonEncode, utf8;

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show BlobOperations, createBlobDatabasePlugin;

import 'aws_cloudfront_client.dart'
    show AwsCloudFrontClient, AwsCloudFrontClientLike, AwsCloudFrontConfig;
import 'aws_config.dart' show AwsS3StorageConfig, applyS3RuntimeAwsConfig;
import 'aws_s3_client.dart' show AwsS3Client, AwsS3ClientLike;

/// Thrown when an S3 object is archived (Glacier) and cannot be read.
class S3ArchivedObjectError implements Exception {
  S3ArchivedObjectError({required this.key, required this.cause});

  final String key;
  final Object cause;

  @override
  String toString() =>
      'S3ArchivedObjectError: object "$key" is archived and cannot be read.';
}

/// Build `toStorageKey` / `fromStorageKey` transformers for a base path.
/// Faithful port of hot-updater `createDatabaseKeyBuilder.ts`.
(String Function(String), String Function(String)) createDatabaseKeyBuilder(
  String? basePath,
) {
  final normalized = basePath?.replaceAll(RegExp(r'^/+|/+$'), '') ?? '';
  String toStorageKey(String key) =>
      [normalized, key].where((s) => s.isNotEmpty).join('/');
  String fromStorageKey(String key) {
    if (normalized.isEmpty) return key;
    final prefix = '$normalized/';
    return key.startsWith(prefix) ? key.substring(prefix.length) : key;
  }

  return (toStorageKey, fromStorageKey);
}

/// Configuration for the AWS S3 blob database plugin.
class S3DatabaseConfig {
  S3DatabaseConfig({
    required this.bucketName,
    required this.region,
    required this.accessKeyId,
    required this.secretAccessKey,
    this.basePath,
    this.cloudfrontDistributionId,
    this.shouldWaitForInvalidation = false,
    this.apiBasePath = '/api/check-update',
    this.endpoint,
    this.sessionToken,
    this.clientFactory = defaultAwsS3DatabaseClientFactory,
    this.cloudfrontClientFactory = defaultAwsCloudFrontClientFactory,
  });

  final String bucketName;
  final String region;
  final String accessKeyId;
  final String secretAccessKey;
  final String? basePath;
  final String? cloudfrontDistributionId;
  final bool shouldWaitForInvalidation;
  final String apiBasePath;
  final String? endpoint;
  final String? sessionToken;

  /// Test seam: override the concrete S3 client.
  final AwsS3ClientLike Function(S3DatabaseConfig config) clientFactory;

  /// Test seam: override the concrete CloudFront client.
  final AwsCloudFrontClientLike Function(S3DatabaseConfig config)
      cloudfrontClientFactory;
}

/// Default factory producing a real [AwsS3Client] with runtime region applied.
AwsS3ClientLike defaultAwsS3DatabaseClientFactory(S3DatabaseConfig config) =>
    AwsS3Client(
      applyS3RuntimeAwsConfig(
        AwsS3StorageConfig(
          bucketName: config.bucketName,
          region: config.region,
          accessKeyId: config.accessKeyId,
          secretAccessKey: config.secretAccessKey,
          basePath: config.basePath,
          endpoint: config.endpoint,
          sessionToken: config.sessionToken,
        ),
      ),
    );

/// Default factory producing a real [AwsCloudFrontClient].
AwsCloudFrontClientLike defaultAwsCloudFrontClientFactory(
  S3DatabaseConfig config,
) =>
    AwsCloudFrontClient(
      AwsCloudFrontConfig(
        accessKeyId: config.accessKeyId,
        secretAccessKey: config.secretAccessKey,
        sessionToken: config.sessionToken,
      ),
    );

bool _isUpdateJsonKey(String key) =>
    RegExp(r'^[^/]+/(?:ios|android)/[^/]+/update\.json$').hasMatch(key);

/// S3-backed [BlobOperations] for the AWS `s3Database` plugin.
class S3BlobOperations implements BlobOperations {
  S3BlobOperations(this.config)
      : _client = config.clientFactory(config),
        _cloudfront = config.cloudfrontDistributionId != null
            ? config.cloudfrontClientFactory(config)
            : null {
    final keyBuilder = createDatabaseKeyBuilder(config.basePath);
    _toStorageKey = keyBuilder.$1;
    _fromStorageKey = keyBuilder.$2;
  }

  final S3DatabaseConfig config;
  final AwsS3ClientLike _client;
  final AwsCloudFrontClientLike? _cloudfront;
  late final String Function(String) _toStorageKey;
  late final String Function(String) _fromStorageKey;

  @override
  String get apiBasePath => config.apiBasePath;

  @override
  Future<List<String>> listObjects(String prefix) async {
    final objects = await _client.listObjects(_toStorageKey(prefix));
    return objects
        .map((o) => _fromStorageKey(o.key))
        .where(_isUpdateJsonKey)
        .toList();
  }

  @override
  Future<T?> loadObject<T>(String key) async {
    final fullKey = _toStorageKey(key);
    try {
      final body = await _client.getObjectAsString(fullKey);
      return jsonDecode(body) as T?;
    } on Exception catch (e) {
      if (e.toString().contains('NoSuchKey')) return null;
      if (e.toString().contains('InvalidObjectState') ||
          e.toString().contains('Archived')) {
        throw S3ArchivedObjectError(key: fullKey, cause: e);
      }
      rethrow;
    }
  }

  @override
  Future<void> uploadObject<T>(String key, T data) async {
    await _client.putObject(
      _toStorageKey(key),
      utf8.encode(jsonEncode(data)),
      'application/json',
    );
  }

  @override
  Future<void> deleteObject(String key) async {
    await _client.deleteObject(_toStorageKey(key));
  }

  @override
  bool shouldSkipLoadObjectError(Object error, String key) =>
      error is S3ArchivedObjectError;

  @override
  void validateChannel(String channel) {
    // hot-updater's s3Database leaves channel validation optional (no-op).
  }

  @override
  Future<void> invalidatePaths(List<String> paths) async {
    final distributionId = config.cloudfrontDistributionId;
    if (_cloudfront == null || distributionId == null || paths.isEmpty) {
      return;
    }
    await _cloudfront.createInvalidation(
      distributionId,
      paths,
      shouldWait: config.shouldWaitForInvalidation,
    );
  }
}

/// AWS S3 blob database plugin (faithful port of hot-updater `s3Database.ts`).
///
/// Stores bundles as JSON (`update.json`) under
/// `channel/platform/targetAppVersion/` paths and serves them via
/// `createBlobDatabasePlugin`, invalidating CloudFront paths on writes.
final s3Database = createBlobDatabasePlugin<S3DatabaseConfig>(
  name: 's3Database',
  blobFactory: (config) => S3BlobOperations(config),
);
