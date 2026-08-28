import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart';

import 'postgres_client.dart';
import 'postgres_config.dart';

/// Configuration for the Postgres bytea storage plugin.
///
/// Reuses the same [PostgresConfig] connection as the database plugin. Blob
/// bytes are stored in a `flutter_patcher_storage(key text primary key, data
/// bytea, content_type text)` table. Because Postgres cannot serve bytes over
/// HTTP itself, [servingBaseUrl] may point at a thin proxy that reads from this
/// table so device update-checks can download over HTTP (the CLI/console supply
/// one; tests mount a local server).
class PostgresStorageConfig {
  const PostgresStorageConfig({
    required this.db,
    this.basePath,
    this.servingBaseUrl,
  });

  final PostgresConfig db;
  final String? basePath;
  final String? servingBaseUrl;
}

/// Resolves the storage client for a config (test seam via [PostgresConfig.clientFactory]).
PostgresClientLike resolvePostgresStorageClient(PostgresStorageConfig config) =>
    config.db.clientFactory?.call(config.db) ?? PostgresClient.connect(config.db);

String _storageUri(String key, String? servingBaseUrl) {
  if (servingBaseUrl != null && servingBaseUrl.isNotEmpty) {
    final base = servingBaseUrl.endsWith('/')
        ? servingBaseUrl.substring(0, servingBaseUrl.length - 1)
        : servingBaseUrl;
    return '$base/$key';
  }
  return 'postgres://$key';
}

String _contentType(String key) {
  if (key.endsWith('.json')) return 'application/json';
  if (key.endsWith('.zip')) return 'application/zip';
  return 'application/octet-stream';
}

String _strip(String storageUri, String? servingBaseUrl) {
  if (storageUri.startsWith('postgres://')) {
    return storageUri.substring('postgres://'.length);
  }
  if (servingBaseUrl != null && storageUri.startsWith(servingBaseUrl)) {
    final base =
        servingBaseUrl.endsWith('/') ? servingBaseUrl : '$servingBaseUrl/';
    return storageUri.startsWith(base)
        ? storageUri.substring(base.length)
        : storageUri;
  }
  return storageUri;
}

Uint8List _toBytes(Object? data) {
  if (data is Uint8List) return data;
  if (data is List) return Uint8List.fromList(data.cast<int>());
  return Uint8List(0);
}

NodeStorageProfile createPostgresNodeProfile(
  PostgresClientLike client,
  String? basePath,
  String? servingBaseUrl,
) =>
    _PostgresNodeProfile(client, basePath, servingBaseUrl);

class _PostgresNodeProfile implements NodeStorageProfile {
  _PostgresNodeProfile(this._client, this._basePath, this._servingBaseUrl);

  final PostgresClientLike _client;
  final String? _basePath;
  final String? _servingBaseUrl;

  String _withBase(String key) =>
      [_basePath, key].where((s) => s != null && s.isNotEmpty).join('/');

  @override
  Future<Map<String, String>> upload(String key, String filePath) async {
    final fullKey = _withBase(key);
    final bytes = await File(filePath).readAsBytes();
    await _client.execute(
      'INSERT INTO flutter_patcher_storage (key, data, content_type) '
      'VALUES (@key, @data, @ct) '
      'ON CONFLICT (key) DO UPDATE SET data = EXCLUDED.data, content_type = EXCLUDED.content_type',
      {
        '@key': fullKey,
        '@data': bytes,
        '@ct': _contentType(fullKey),
      },
    );
    return {'storageUri': _storageUri(fullKey, _servingBaseUrl)};
  }

  @override
  Future<bool> exists(String storageUri) async {
    final key = _strip(storageUri, _servingBaseUrl);
    final rows = await _client.execute(
      'SELECT 1 FROM flutter_patcher_storage WHERE key = @key',
      {'@key': key},
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> delete(String storageUri) async {
    await _client.execute(
      'DELETE FROM flutter_patcher_storage WHERE key = @key',
      {'@key': _strip(storageUri, _servingBaseUrl)},
    );
  }

  @override
  Future<void> downloadFile(String storageUri, String filePath) async {
    final key = _strip(storageUri, _servingBaseUrl);
    final rows = await _client.execute(
      'SELECT data FROM flutter_patcher_storage WHERE key = @key',
      {'@key': key},
    );
    if (rows.isEmpty) {
      throw StateError('Object not found: $key');
    }
    await File(filePath).writeAsBytes(_toBytes(rows.first['data']));
  }

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async {
    final fullPrefix = prefix == null ? null : _withBase(prefix);
    final rows = await _client.execute(
      'SELECT key, octet_length(data) AS size FROM flutter_patcher_storage '
      'WHERE key LIKE @prefix',
      {'@prefix': '${fullPrefix ?? ''}%'},
    );
    return rows.map((r) {
      final key = r['key'] as String;
      return StorageObject(
        key: key,
        storageUri: _storageUri(key, _servingBaseUrl),
        size: (r['size'] as int?) ?? 0,
      );
    }).toList();
  }

  @override
  Future<void> deleteObjects(List<String> keys) async {
    for (final k in keys) {
      await _client.execute(
        'DELETE FROM flutter_patcher_storage WHERE key = @key',
        {'@key': _strip(k, _servingBaseUrl)},
      );
    }
  }
}

RuntimeStorageProfile createPostgresRuntimeProfile(
  PostgresClientLike client,
  String? servingBaseUrl,
) =>
    _PostgresRuntimeProfile(client, servingBaseUrl);

class _PostgresRuntimeProfile implements RuntimeStorageProfile {
  _PostgresRuntimeProfile(this._client, this._servingBaseUrl);

  final PostgresClientLike _client;
  final String? _servingBaseUrl;

  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async {
    return {'fileUrl': _storageUri(_strip(storageUri, _servingBaseUrl), _servingBaseUrl)};
  }

  @override
  Future<String?> readText(String storageUri) async {
    final key = _strip(storageUri, _servingBaseUrl);
    final rows = await _client.execute(
      'SELECT data FROM flutter_patcher_storage WHERE key = @key',
      {'@key': key},
    );
    if (rows.isEmpty) return null;
    return utf8.decode(_toBytes(rows.first['data']));
  }
}

/// Postgres bytea storage plugin (name `postgresStorage`, protocol `postgres`).
StoragePlugin Function(PostgresStorageConfig) postgresStorage =
    createUniversalStoragePlugin<PostgresStorageConfig>(
      name: 'postgresStorage',
      supportedProtocol: 'postgres',
      factory: (cfg) {
        final client = resolvePostgresStorageClient(cfg);
        return (
          node: createPostgresNodeProfile(client, cfg.basePath, cfg.servingBaseUrl),
          runtime: createPostgresRuntimeProfile(client, cfg.servingBaseUrl),
        );
      },
    );
