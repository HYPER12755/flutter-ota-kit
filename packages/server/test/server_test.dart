import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:flutter_patcher_cloudflare/flutter_patcher_cloudflare.dart'
    show d1Database;
import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show Bundle, Platform, nilUuid;
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show
        DatabasePlugin,
        NodeStorageProfile,
        RuntimeStorageProfile,
        StorageObject,
        StoragePlugin,
        StoragePluginProfiles;
import 'package:flutter_patcher_server/flutter_patcher_server.dart'
    show createHotUpdater, HandlerRoutes, ServerOptions;
import 'package:shelf/shelf.dart' show Handler, Request, Response;
import 'package:test/test.dart';

import '../../../plugins/cloudflare/test/mock_d1_client.dart' show Store, mockConfig;

const String _nil = nilUuid;

/// Tiny in-memory storage so the server can resolve `fileUrl`.
class _MemStorage extends StoragePlugin {
  _MemStorage()
      : _profiles = StoragePluginProfiles(
          node: _Node({}),
          runtime: _Runtime(),
        );

  final StoragePluginProfiles _profiles;

  @override
  String get name => 'memStorage';
  @override
  String get supportedProtocol => 'mem';

  @override
  StoragePluginProfiles get profiles => _profiles;
}

class _Node implements NodeStorageProfile {
  _Node(this._store);
  final Map<String, List<int>> _store;
  String _strip(String uri) => uri.replaceFirst('mem://bucket/', '');
  @override
  Future<Map<String, String>> upload(String key, String filePath) async =>
      {'storageUri': 'mem://bucket/$key'};
  @override
  Future<bool> exists(String storageUri) async =>
      _store.containsKey(_strip(storageUri));
  @override
  Future<void> delete(String storageUri) async => _store.remove(_strip(storageUri));
  @override
  Future<void> downloadFile(String storageUri, String filePath) async {}
  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async => [];
  @override
  Future<void> deleteObjects(List<String> keys) async =>
      keys.forEach(_store.remove);
}

class _Runtime implements RuntimeStorageProfile {
  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async =>
      {'fileUrl': 'https://cdn.example.com/${_strip(storageUri)}'};
  @override
  Future<String?> readText(String storageUri) async => null;
}

String _strip(String uri) => uri.replaceFirst('mem://bucket/', '');

Future<Response> _call(
  Handler handler,
  String method,
  String path, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final request = Request(
    method,
    Uri.parse('http://localhost$path'),
    headers: headers,
    body: body == null ? null : (body is String ? body : jsonEncode(body)),
  );
  final response = await handler(request);
  return response;
}

Future<Map<String, dynamic>> _json(Response res) async =>
    jsonDecode(await res.readAsString());

void main() {
  late Store store;
  late DatabasePlugin database;
  late StoragePlugin storage;
  late Handler handler;

  setUp(() {
    store = Store();
    database = d1Database(mockConfig(store))();
    storage = _MemStorage();
    handler = createHotUpdater(
      ServerOptions(
        database: database,
        storages: [storage],
        routes: const HandlerRoutes(updateCheck: true, bundles: true),
      ),
    ).handler;
  });

  Future<void> seedBundles() async {
    await database.appendBundle(
      Bundle(
        id: 'b1',
        channel: 'production',
        enabled: true,
        shouldForceUpdate: false,
        fileHash: 'h-b1',
        platform: Platform.android,
        targetAppVersion: '1.0.0',
        storageUri: 'mem://bucket/b1.zip',
        fingerprintHash: 'fp-b1',
        message: 'msg',
        patches: null,
      ),
    );
    await database.commitBundle();
  }

  group('flutter_patcher_server', () {
    test('GET /api/version returns server version', () async {
      final res = await _call(handler, 'GET', '/api/version');
      expect(res.statusCode, 200);
      expect((await _json(res))['version'], isA<String>());
    });

    test('update-check (appVersion) returns fileUrl', () async {
      await seedBundles();
      final res = await _call(
        handler,
        'GET',
        '/api/app-version/android/1.0.0/production/$_nil/$_nil',
      );
      expect(res.statusCode, 200);
      final body = await _json(res);
      expect(body['id'], 'b1');
      expect(body['fileUrl'], 'https://cdn.example.com/b1.zip');
    });

    test('update-check (fingerprint) returns fileUrl', () async {
      await seedBundles();
      final res = await _call(
        handler,
        'GET',
        '/api/fingerprint/android/fp-b1/production/$_nil/$_nil',
      );
      expect(res.statusCode, 200);
      final body = await _json(res);
      expect(body['id'], 'b1');
      expect(body['fileUrl'], isNotNull);
    });

    test('explicit no-update when SDK >= 0.31.0 and none available', () async {
      final res = await _call(
        handler,
        'GET',
        '/api/app-version/android/9.9.9/production/$_nil/$_nil',
        headers: {'hot-updater-sdk-version': '1.0.0'},
      );
      expect(res.statusCode, 200);
      expect((await _json(res))['status'], 'UP_TO_DATE');
    });

    test('bundle management routes (POST/PATCH/GET/DELETE/channels)', () async {
      final created = await _call(handler, 'POST', '/api/bundles', body: {
        'id': 'b2',
        'channel': 'production',
        'enabled': true,
        'shouldForceUpdate': false,
        'fileHash': 'h-b2',
        'platform': 'android',
        'targetAppVersion': '2.0.0',
        'storageUri': 'mem://bucket/b2.zip',
        'fingerprintHash': 'fp-b2',
        'message': 'm',
      });
      expect(created.statusCode, 201);

      final list = await _call(handler, 'GET', '/api/bundles?channel=production');
      expect(list.statusCode, 200);
      expect((await _json(list))['data'], hasLength(1));

      final patched = await _call(handler, 'PATCH', '/api/bundles/b2', body: {
        'enabled': false,
      });
      expect(patched.statusCode, 200);

      final channels = await _call(handler, 'GET', '/api/bundles/channels');
      expect(
        (await _json(channels))['data']['channels'],
        contains('production'),
      );

      final deleted = await _call(handler, 'DELETE', '/api/bundles/b2');
      expect(deleted.statusCode, 200);
    });

    test('unknown route returns 404', () async {
      final res = await _call(handler, 'GET', '/api/nope');
      expect(res.statusCode, 404);
    });
  });
}
