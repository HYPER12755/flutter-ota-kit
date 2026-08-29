import 'package:path/path.dart' show basename;

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show
        NodeStorageProfile,
        RuntimeStorageProfile,
        StorageObject,
        createStorageKeyBuilder,
        getContentType,
        parseStorageUri;

import 'aws_config.dart' show AwsS3StorageConfig, resolveAwsS3Client;
import 'aws_s3_client.dart' show AwsS3ClientLike, readFileBytes, writeFileBytes;

void _ensureExpectedBucket(String bucket, String bucketName) {
  if (bucket != bucketName) {
    throw ArgumentError(
      'Bucket name mismatch: expected "$bucketName", but found "$bucket".',
    );
  }
}

/// Build the node (deploy/CLI) storage profile for AWS S3.
NodeStorageProfile createS3StorageProfile(AwsS3StorageConfig config) {
  final AwsS3ClientLike client = resolveAwsS3Client(config);
  final getStorageKey = createStorageKeyBuilder(config.basePath);

  return _S3NodeProfile(client, config, getStorageKey);
}

/// Build the runtime (update-check) storage profile for AWS S3.
RuntimeStorageProfile createS3RuntimeStorageProfile(AwsS3StorageConfig config) {
  final AwsS3ClientLike client = resolveAwsS3Client(config);
  return _S3RuntimeProfile(client, config);
}

class _S3NodeProfile implements NodeStorageProfile {
  _S3NodeProfile(this._client, this._config, this._getStorageKey);

  final AwsS3ClientLike _client;
  final AwsS3StorageConfig _config;
  final String Function(String, [String, String, String]) _getStorageKey;

  String _getListPrefix(String prefix) {
    final normalizedPrefix = prefix.replaceAll(RegExp(r'^/+|/+$'), '');
    final value = [_config.basePath ?? '', normalizedPrefix]
        .where((s) => s.isNotEmpty)
        .join('/');
    return value.isNotEmpty ? '$value/' : '';
  }

  @override
  Future<Map<String, String>> upload(String key, String filePath) async {
    final bytes = await readFileBytes(filePath);
    final contentType = getContentType(filePath);
    final filename = basename(filePath);
    final storageKey = _getStorageKey(key, filename);

    await _client.putObject(storageKey, bytes, contentType);
    return {'storageUri': 's3://${_config.bucketName}/$storageKey'};
  }

  @override
  Future<bool> exists(String storageUri) async {
    final parsed = parseStorageUri(storageUri, 's3');
    _ensureExpectedBucket(parsed.bucket, _config.bucketName);
    return _client.headObject(parsed.key);
  }

  @override
  Future<void> delete(String storageUri) async {
    final parsed = parseStorageUri(storageUri, 's3');
    _ensureExpectedBucket(parsed.bucket, _config.bucketName);

    final list = await _client.listObjects(parsed.key);
    if (list.isEmpty) {
      throw StateError('Bundle Not Found');
    }
    await _client.deleteObjects(list.map((o) => o.key).toList());
  }

  @override
  Future<void> downloadFile(String storageUri, String filePath) async {
    final parsed = parseStorageUri(storageUri, 's3');
    _ensureExpectedBucket(parsed.bucket, _config.bucketName);
    final bytes = await _client.getObjectAsBytes(parsed.key);
    await writeFileBytes(filePath, bytes);
  }

  String _getRelativeKey(String key) {
    final bp = _config.basePath;
    if (bp != null && bp.isNotEmpty && key.startsWith(bp)) {
      var stripped = key.substring(bp.length);
      if (stripped.startsWith('/')) stripped = stripped.substring(1);
      return stripped;
    }
    return key;
  }

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async {
    final list = await _client.listObjects(
      prefix == null ? null : _getListPrefix(prefix),
    );
    return list.map((o) {
      final relativeKey = _getRelativeKey(o.key);
      return StorageObject(
        key: relativeKey,
        storageUri: 's3://${_config.bucketName}/$relativeKey',
        size: o.size,
        lastModifiedAt: o.lastModifiedAt,
      );
    }).toList();
  }

  @override
  Future<void> deleteObjects(List<String> keys) =>
      _client.deleteObjects(keys.map(_getStorageKey).toList());
}

class _S3RuntimeProfile implements RuntimeStorageProfile {
  _S3RuntimeProfile(this._client, this._config);

  final AwsS3ClientLike _client;
  final AwsS3StorageConfig _config;

  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async {
    final parsed = parseStorageUri(storageUri, 's3');
    _ensureExpectedBucket(parsed.bucket, _config.bucketName);
    final fileUrl = await _client.getPresignedUrl(parsed.key);
    return {'fileUrl': fileUrl};
  }

  @override
  Future<String?> readText(String storageUri) async {
    final parsed = parseStorageUri(storageUri, 's3');
    _ensureExpectedBucket(parsed.bucket, _config.bucketName);
    try {
      return await _client.getObjectAsString(parsed.key);
    } catch (_) {
      return null;
    }
  }
}
