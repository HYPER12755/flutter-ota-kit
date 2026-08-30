import 'package:path/path.dart' show basename;

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show
        NodeStorageProfile,
        RuntimeStorageProfile,
        StorageObject,
        createStorageKeyBuilder,
        ensureExpectedBucket,
        getContentType,
        parseStorageUri;

import 'r2_config.dart' show R2S3StorageConfig, resolveR2Client;
import 'r2_s3_client.dart' show R2S3ClientLike, readFileBytes, writeFileBytes;

/// Build the node (deploy/CLI) storage profile for R2 S3.
NodeStorageProfile createS3StorageProfile(R2S3StorageConfig config) {
  final R2S3ClientLike client = resolveR2Client(config);
  final getStorageKey = createStorageKeyBuilder(config.basePath);

  return _R2NodeProfile(client, config, getStorageKey);
}

/// Build the runtime (update-check) storage profile for R2 S3.
RuntimeStorageProfile createS3RuntimeStorageProfile(R2S3StorageConfig config) {
  final R2S3ClientLike client = resolveR2Client(config);
  return _R2RuntimeProfile(client, config);
}

class _R2NodeProfile implements NodeStorageProfile {
  _R2NodeProfile(this._client, this._config, this._getStorageKey);

  final R2S3ClientLike _client;
  final R2S3StorageConfig _config;
  final String Function(String, [String, String, String]) _getStorageKey;

  @override
  Future<Map<String, String>> upload(String key, String filePath) async {
    final bytes = await readFileBytes(filePath);
    final contentType = getContentType(filePath);
    final filename = basename(filePath);
    final storageKey = _getStorageKey(key, filename);

    await _client.putObject(storageKey, bytes, contentType);
    return {'storageUri': 'r2://${_config.bucketName}/$storageKey'};
  }

  @override
  Future<bool> exists(String storageUri) async {
    final parsed = parseStorageUri(storageUri, 'r2');
    ensureExpectedBucket(parsed.bucket, _config.bucketName);
    return _client.headObject(parsed.key);
  }

  @override
  Future<void> delete(String storageUri) async {
    final parsed = parseStorageUri(storageUri, 'r2');
    ensureExpectedBucket(parsed.bucket, _config.bucketName);
    await _client.deleteObject(parsed.key);
  }

  @override
  Future<void> downloadFile(String storageUri, String filePath) async {
    final parsed = parseStorageUri(storageUri, 'r2');
    ensureExpectedBucket(parsed.bucket, _config.bucketName);
    final bytes = await _client.getObjectAsBytes(parsed.key);
    await writeFileBytes(filePath, bytes);
  }

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) =>
      _client.listObjects(prefix);

  @override
  Future<void> deleteObjects(List<String> keys) =>
      _client.deleteObjects(keys);
}

class _R2RuntimeProfile implements RuntimeStorageProfile {
  _R2RuntimeProfile(this._client, this._config);

  final R2S3ClientLike _client;
  final R2S3StorageConfig _config;

  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async {
    final parsed = parseStorageUri(storageUri, 'r2');
    ensureExpectedBucket(parsed.bucket, _config.bucketName);
    final fileUrl = await _client.getSignedUrl(parsed.key);
    return {'fileUrl': fileUrl};
  }

  @override
  Future<String?> readText(String storageUri) async {
    final parsed = parseStorageUri(storageUri, 'r2');
    ensureExpectedBucket(parsed.bucket, _config.bucketName);
    try {
      return await _client.getObjectAsString(parsed.key);
    } catch (_) {
      return null;
    }
  }
}
