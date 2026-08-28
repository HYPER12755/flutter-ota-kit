import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show File;

import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show
        NodeStorageProfile,
        RuntimeStorageProfile,
        StorageObject,
        createUniversalStoragePlugin;
import 'package:http/http.dart' as http;
import 'package:http/http.dart';

import 'standalone_config.dart'
    show
        StandaloneStorageConfig,
        StandaloneStorageRoutes,
        joinUrl,
        mergeHeaders;

/// Single-curried standalone storage factory.
///
/// Faithful port of hot-updater `plugins/standalone/src/standaloneStorage.ts`.
StoragePluginLike standaloneStorage(StandaloneStorageConfig config) =>
    createUniversalStoragePlugin<StandaloneStorageConfig>(
      name: 'standalone-storage',
      supportedProtocol: 'http',
      factory: (c) {
        final storage = _StandaloneStorage(c);
        return (node: storage, runtime: storage);
      },
    )(config);

/// Alias so the curried factory can be used uniformly with other backends.
typedef StoragePluginLike = dynamic;

class _StandaloneStorage implements NodeStorageProfile, RuntimeStorageProfile {
  _StandaloneStorage(this.config)
      : routes = config.routes ?? const StandaloneStorageRoutes();

  final StandaloneStorageConfig config;
  final StandaloneStorageRoutes routes;

  Client _client() => config.clientFactory?.call() ?? http.Client();

  Map<String, String> _headers([Map<String, String>? extra]) =>
      mergeHeaders(config.commonHeaders, extra);

  // --- Node profile ---------------------------------------------------------

  @override
  Future<Map<String, String>> upload(String key, String filePath) async {
    final client = _client();
    final bytes = await File(filePath).readAsBytes();
    final uri = Uri.parse(joinUrl(config.baseUrl, routes.upload))
        .replace(queryParameters: {'key': key});
    final res = await client.post(
      uri,
      headers: _headers({'Content-Type': 'application/octet-stream'}),
      body: bytes,
    );
    if (res.statusCode >= 400) {
      throw StateError(
        'standalone storage upload failed (${res.statusCode}): ${res.body}',
      );
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final storageUri = decoded['storageUri'] as String?;
    if (storageUri == null) {
      throw StateError('standalone storage upload returned no storageUri');
    }
    return {'storageUri': storageUri};
  }

  @override
  Future<bool> exists(String storageUri) async {
    final fileUrl = (await getDownloadUrl(storageUri))['fileUrl'];
    if (fileUrl == null) return false;
    final client = _client();
    final res = await client.head(Uri.parse(fileUrl));
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  @override
  Future<void> delete(String storageUri) async {
    final client = _client();
    final res = await client.delete(
      Uri.parse(joinUrl(config.baseUrl, routes.delete)),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({'storageUri': storageUri}),
    );
    if (res.statusCode >= 400) {
      throw StateError(
        'standalone storage delete failed (${res.statusCode}): ${res.body}',
      );
    }
  }

  @override
  Future<void> downloadFile(String storageUri, String filePath) async {
    final fileUrl = (await getDownloadUrl(storageUri))['fileUrl'];
    if (fileUrl == null) {
      throw StateError('standalone storage could not resolve download url');
    }
    final client = _client();
    final res = await client.get(Uri.parse(fileUrl));
    if (res.statusCode >= 400) {
      throw StateError(
        'standalone storage download failed (${res.statusCode})',
      );
    }
    await File(filePath).writeAsBytes(res.bodyBytes);
  }

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async {
    final client = _client();
    final uri = Uri.parse(joinUrl(config.baseUrl, routes.list))
        .replace(queryParameters: prefix != null ? {'prefix': prefix} : null);
    final res = await client.get(uri);
    if (res.statusCode >= 400) return const [];
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (decoded['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return data
        .map((o) => StorageObject(
              key: o['key'] as String,
              storageUri: o['storageUri'] as String,
              size: o['size'] as int? ?? 0,
            ))
        .toList();
  }

  @override
  Future<void> deleteObjects(List<String> keys) async {
    for (final key in keys) {
      await delete(key);
    }
  }

  // --- Runtime profile ------------------------------------------------------

  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async {
    final client = _client();
    final res = await client.post(
      Uri.parse(joinUrl(config.baseUrl, routes.getDownloadUrl)),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({'storageUri': storageUri}),
    );
    if (res.statusCode >= 400) {
      throw StateError(
        'standalone storage getDownloadUrl failed (${res.statusCode}): '
        '${res.body}',
      );
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final fileUrl = decoded['fileUrl'] as String?;
    if (fileUrl == null) {
      throw StateError('standalone storage getDownloadUrl returned no fileUrl');
    }
    return {'fileUrl': fileUrl};
  }

  @override
  Future<String?> readText(String storageUri) async {
    final client = _client();
    final res = await client.post(
      Uri.parse(joinUrl(config.baseUrl, routes.readText)),
      headers: _headers({'Content-Type': 'application/json'}),
      body: jsonEncode({'storageUri': storageUri}),
    );
    if (res.statusCode >= 400) return null;
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return decoded['data'] as String?;
  }
}
