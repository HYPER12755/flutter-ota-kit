import 'dart:convert' show jsonDecode, utf8;
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_patcher_client/flutter_patcher_client.dart';
import 'package:flutter_patcher_cloudflare/flutter_patcher_cloudflare.dart'
    show d1Database;
import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show Bundle, Platform, UpdateStrategy;
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show
        DatabasePlugin,
        NodeStorageProfile,
        RuntimeStorageProfile,
        StorageObject,
        StoragePlugin,
        StoragePluginProfiles;
import 'package:flutter_patcher_server/flutter_patcher_server.dart'
    show HandlerRoutes, ServerOptions, createHotUpdater;
import 'package:shelf/shelf.dart' show Handler, Request;
import 'package:test/test.dart';

import '../../../plugins/cloudflare/test/mock_d1_client.dart' show Store, mockConfig;

/// Storage plugin whose runtime profile maps a `mem://` storage URI to a real
/// localhost HTTP endpoint serving the bundle bytes (so the client can actually
/// download the payload — proving the full pull path end to end).
class _LocalStorage extends StoragePlugin {
  _LocalStorage(this._base);
  final String _base;

  @override
  String get name => 'localStorage';
  @override
  String get supportedProtocol => 'mem';

  @override
  StoragePluginProfiles get profiles => StoragePluginProfiles(
        node: _Node(),
        runtime: _Runtime(_base),
      );
}

class _Node implements NodeStorageProfile {
  @override
  Future<Map<String, String>> upload(String key, String filePath) async =>
      {'storageUri': 'mem://bucket/$key'};
  @override
  Future<bool> exists(String storageUri) async => true;
  @override
  Future<void> delete(String storageUri) async {}
  @override
  Future<void> downloadFile(String storageUri, String filePath) async {}
  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async => [];
  @override
  Future<void> deleteObjects(List<String> keys) async {}
}

class _Runtime implements RuntimeStorageProfile {
  _Runtime(this._base);
  final String _base;
  String _key(String storageUri) =>
      storageUri.replaceFirst('mem://bucket/', '');
  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async =>
      {'fileUrl': '$_base/${_key(storageUri)}'};
  @override
  Future<String?> readText(String storageUri) async => null;
}

/// Routes an HTTP GET to the in-process shelf [handler] (no real socket).
Future<Map<String, dynamic>> _serverGetJson(
  Handler handler,
  String url, {
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final uri = Uri.parse(url);
  final request = Request('GET', uri, headers: headers ?? const {});
  final response = await handler(request);
  final body = await response.readAsString();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('HTTP ${response.statusCode}');
  }
  if (body == 'null' || body.isEmpty) return {};
  final decoded = jsonDecode(body);
  if (decoded == null) return {};
  return Map<String, dynamic>.from(decoded);
}

void main() {
  late HttpServer storageServer;
  late String storageBase;
  late List<int> payloadBytes;
  late String payloadMd5;
  late DatabasePlugin db;
  late Handler handler;

  setUpAll(() async {
    payloadBytes = utf8.encode('FAKE_BUNDLE_ZIP_${'x' * 4096}');
    payloadMd5 = crypto.md5.convert(payloadBytes).toString();

    storageServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    storageBase =
        'http://${storageServer.address.host}:${storageServer.port}';
    storageServer.listen((req) async {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..add(payloadBytes);
      await req.response.close();
    });

    final store = Store();
    db = d1Database(mockConfig(store))();
    handler = createHotUpdater(ServerOptions(
      database: db,
      storages: [_LocalStorage(storageBase)],
      routes: const HandlerRoutes(updateCheck: true, bundles: false),
    )).handler;
  });

  tearDownAll(() => storageServer.close());

  ServerUpdateSource clientFor(Handler h) => ServerUpdateSource(
        getJson: (url, {headers, required Duration timeout}) =>
            _serverGetJson(h, url, headers: headers, timeout: timeout),
      );

  Future<void> seed({
    required String id,
    required String channel,
    required String fingerprintHash,
    String targetAppVersion = '1.0.0',
  }) async {
    await db.appendBundle(Bundle(
      id: id,
      channel: channel,
      enabled: true,
      shouldForceUpdate: false,
      fileHash: payloadMd5,
      platform: Platform.android,
      targetAppVersion: targetAppVersion,
      storageUri: 'mem://bucket/$id.zip',
      fingerprintHash: fingerprintHash,
      message: 'update $id',
    ));
    await db.commitBundle();
  }

  test('fingerprint update-check returns PatchInfo with downloadable URL',
      () async {
    await seed(id: 'b1', channel: 'production', fingerprintHash: 'fp-b1');

    final result = await clientFor(handler).check(ServerUpdateConfig(
      baseUrl: 'http://localhost',
      channel: 'production',
      platform: Platform.android,
      updateStrategy: UpdateStrategy.fingerprint,
      fingerprintHash: 'fp-b1',
    ));

    expect(result.isUpToDate, isFalse);
    expect(result.patch, isNotNull);
    expect(result.patch!.version, 'b1');
    expect(result.patch!.md5, payloadMd5);
    expect(result.patch!.patchUrl, '$storageBase/b1.zip');

    // Prove the resolved download URL actually serves the payload bytes.
    final uri = Uri.parse(result.patch!.patchUrl);
    final http = HttpClient();
    final req = await http.getUrl(uri);
    final resp = await req.close();
    final bytes = await resp.fold<List<int>>(
      <int>[],
      (b, c) => b..addAll(c),
    );
    http.close();
    expect(bytes, payloadBytes);
  });

  test('appVersion update-check matches targetAppVersion', () async {
    await seed(id: 'b1', channel: 'production', fingerprintHash: 'fp-b1');

    final result = await clientFor(handler).check(ServerUpdateConfig(
      baseUrl: 'http://localhost',
      channel: 'production',
      platform: Platform.android,
      updateStrategy: UpdateStrategy.appVersion,
      appVersion: '1.0.0',
      sdkVersion: '0.1.0',
    ));

    expect(result.patch!.version, 'b1');
    expect(result.status.name, 'update');
  });

  test('explicit no-update when SDK >= 0.31.0 and nothing matches', () async {
    final result = await clientFor(handler).check(ServerUpdateConfig(
      baseUrl: 'http://localhost',
      channel: 'production',
      platform: Platform.android,
      updateStrategy: UpdateStrategy.appVersion,
      appVersion: '9.9.9',
      sdkVersion: '1.0.0',
    ));

    expect(result.isUpToDate, isTrue);
    expect(result.patch, isNull);
  });

  test('channel isolation: wrong channel yields no update', () async {
    await seed(id: 'stg', channel: 'staging', fingerprintHash: 'fp-stg');

    // Query production channel with the staging fingerprint -> no match.
    final result = await clientFor(handler).check(ServerUpdateConfig(
      baseUrl: 'http://localhost',
      channel: 'production',
      platform: Platform.android,
      updateStrategy: UpdateStrategy.fingerprint,
      fingerprintHash: 'fp-stg',
    ));

    expect(result.isUpToDate, isTrue);
  });
}
