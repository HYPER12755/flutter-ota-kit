/// PocketBase-backed [StoragePlugin] implementation.
///
/// Uses PocketBase's built-in file storage (per-collection buckets) for
/// bundle artifacts. Each bundle record carries a single `artifact` file
/// field that stores the patch zip; the storage URI is a `pb://` URL that
/// the runtime resolves to a signed download URL on the client.
library;

import 'dart:io';

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';

import 'pocketbase_client.dart';

/// Configuration for the PocketBase storage plugin.
class PocketBaseStorageConfig {
  const PocketBaseStorageConfig({
    required this.url,
    required this.adminEmail,
    required this.adminPassword,
    required this.bundlesCollection,
    this.bundlesBucket = 'bundles',
    this.basePath,
    this.clientFactory,
  });

  final String url;
  final String adminEmail;
  final String adminPassword;
  final String bundlesCollection;
  final String bundlesBucket;
  final String? basePath;
  final PocketBaseClientFactory? clientFactory;
}

/// Parse a `pb://bundles/{recordId}/{filename}` URI back into its parts.
({String recordId, String filename, String? bucket})? parsePocketBaseStorageUri(
  String storageUri,
) {
  // Accepts both `pb://{bucket}/{id}/{file}` and `pb:///{id}/{file}` (no
  // bucket). The leading double-slash with an optional bucket prefix is
  // matched explicitly.
  final match = RegExp(r'^pb://(?:([^/]*)/)?([^/]+)/(.+)$')
      .firstMatch(storageUri);
  if (match == null) return null;
  final bucket = match.group(1);
  return (
    recordId: match.group(2)!,
    filename: match.group(3)!,
    bucket: (bucket == null || bucket.isEmpty) ? null : bucket,
  );
}

/// Stringify a PocketBase file storage URI.
String buildPocketBaseStorageUri(
  String recordId,
  String filename, [
  String? bucket,
]) => 'pb://${bucket ?? ''}/${recordId}/$filename';

/// PocketBase-backed [StoragePlugin].
class _PocketBaseStorage implements StoragePlugin {
  _PocketBaseStorage(this.config, this.client);

  final PocketBaseStorageConfig config;
  final PocketBaseClient client;

  @override
  String get name => 'pocketbaseStorage';

  @override
  String get supportedProtocol => 'pb:';

  @override
  StoragePluginProfiles get profiles => StoragePluginProfiles(
    node: _PocketBaseNodeStorage(this),
    runtime: _PocketBaseRuntimeStorage(this),
  );
}

/// Runtime profile: URL-oriented operations used by the device SDK
/// (resolve a signed download URL for a `pb://...` storage URI).
class _PocketBaseRuntimeStorage implements RuntimeStorageProfile {
  _PocketBaseRuntimeStorage(this.parent);

  final _PocketBaseStorage parent;

  PocketBaseClient get _client => parent.client;
  PocketBaseStorageConfig get _config => parent.config;

  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async {
    final parsed = parsePocketBaseStorageUri(storageUri);
    if (parsed == null) {
      throw FormatException('Not a pb:// URI: $storageUri');
    }
    // PocketBase file downloads require a short-lived token when the
    // collection's file rules restrict public reads. The server can mint one
    // via `POST /api/files/token` with admin auth.
    final token = await _client.getFileToken(parsed.recordId, parsed.filename);
    final url = _client.fileUrl(
      _config.bundlesCollection,
      parsed.recordId,
      parsed.filename,
      token.isEmpty ? null : token,
    );
    return {'fileUrl': url, 'storageUri': storageUri};
  }

  @override
  Future<String?> readText(String storageUri) async {
    // PB serves binary files only; text reads aren't supported.
    return null;
  }
}

/// Node profile: filesystem-aware operations.
class _PocketBaseNodeStorage implements NodeStorageProfile {
  _PocketBaseNodeStorage(this.parent);

  final _PocketBaseStorage parent;

  PocketBaseClient get _client => parent.client;
  PocketBaseStorageConfig get _config => parent.config;

  String _keyToFilename(String key) =>
      key.replaceAll('/', '_').replaceAll('\\', '_');

  String _baseKey() {
    final bp = _config.basePath;
    return (bp == null || bp.isEmpty) ? '' : '$bp/';
  }

  String _fullKey(String key) => '${_baseKey()}$key';

  @override
  Future<Map<String, String>> upload(String key, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Artifact not found', filePath);
    }
    final bytes = await file.readAsBytes();
    final filename = _keyToFilename(_fullKey(key));
    // PocketBase file storage attaches files to records; use the storage key
    // itself as the record id so callers can pass the bundle id (which the
    // CLI already does) and find the file back via `exists()`.
    final recordId = key;
    final existing = await _client.recordExists(
      _config.bundlesCollection,
      recordId,
    );
    if (!existing) {
      await _client.createRecord<dynamic>(_config.bundlesCollection, {
        'id': recordId,
        'channel': 'pending',
        'platform': 'android',
        'enabled': false,
        'should_force_update': false,
        'file_hash': '',
        'storage_uri': '',
        'rollout_cohort_count': 1000,
      }, (j) => j);
    }
    await _client.uploadFile<dynamic>(
      _config.bundlesCollection,
      recordId,
      'artifact',
      filename,
      bytes,
      fromJson: (j) => j,
    );
    final uri = buildPocketBaseStorageUri(recordId, filename);
    return {'key': _fullKey(key), 'storageUri': uri};
  }

  @override
  Future<bool> exists(String storageUri) async {
    final parsed = parsePocketBaseStorageUri(storageUri);
    if (parsed == null) return false;
    return _client.recordExists(_config.bundlesCollection, parsed.recordId);
  }

  @override
  Future<void> delete(String storageUri) async {
    final parsed = parsePocketBaseStorageUri(storageUri);
    if (parsed == null) return;
    await _client.deleteRecord(_config.bundlesCollection, parsed.recordId);
  }

  @override
  Future<void> downloadFile(String storageUri, String filePath) async {
    final parsed = parsePocketBaseStorageUri(storageUri);
    if (parsed == null) {
      throw FormatException('Not a pb:// URI: $storageUri');
    }
    final token = await _client.getFileToken(parsed.recordId, parsed.filename);
    final url = _client.fileUrl(
      _config.bundlesCollection,
      parsed.recordId,
      parsed.filename,
      token.isEmpty ? null : token,
    );
    final bytes = await _client.downloadFile(url);
    final out = File(filePath);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes);
  }

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async {
    final res = await _client.listRecords<dynamic>(
      _config.bundlesCollection,
      (j) => j,
      perPage: 500,
    );
    final all = res.items.cast<Map>();
    return all
        .map((j) {
          final id = j['id']?.toString() ?? '';
          final filename = j['artifact']?.toString() ?? '';
          if (filename.isEmpty) return null;
          final key = filename.replaceFirst(_baseKey(), '');
          if (prefix != null && prefix.isNotEmpty && !key.startsWith(prefix)) {
            return null;
          }
          return StorageObject(
            key: key,
            storageUri: buildPocketBaseStorageUri(id, filename),
            size: 0,
          );
        })
        .whereType<StorageObject>()
        .toList();
  }

  @override
  Future<void> deleteObjects(List<String> keys) async {
    for (final key in keys) {
      await _client.deleteRecord(_config.bundlesCollection, key);
    }
  }
}

/// Build a `pocketbaseStorage` plugin.
StoragePlugin pocketbaseStorage(PocketBaseStorageConfig config) {
  final client = config.clientFactory != null
      ? config.clientFactory!(
          config.url,
          config.adminEmail,
          config.adminPassword,
        )
      : PocketBaseClient(config.url);
  client.adminCredentials(config.adminEmail, config.adminPassword);
  return _PocketBaseStorage(config, client);
}
