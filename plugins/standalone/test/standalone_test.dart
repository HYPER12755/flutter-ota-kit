import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show Directory, File;

import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show Bundle, FingerprintGetBundlesArgs, Platform;
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show DatabaseBundleQueryOptions;
import 'package:flutter_patcher_standalone/flutter_patcher_standalone.dart'
    show
        StandaloneRepositoryConfig,
        StandaloneStorageConfig,
        standaloneRepository,
        standaloneStorage;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;
import 'package:test/test.dart';

/// A tiny in-memory router for the standalone REST contract.
Future<http.Response> _router(http.Request request) async {
  final path = request.url.path;
  final method = request.method;

  if (path == '/api/bundles/channels' && method == 'GET') {
    return http.Response(
      jsonEncode({'data': {'channels': ['production', 'staging']}}),
      200,
    );
  }
  if (path == '/api/bundles' && method == 'GET') {
    return http.Response(
      jsonEncode({
        'data': [
          {
            'id': 'b1',
            'platform': 'android',
            'channel': 'production',
            'enabled': true,
            'shouldForceUpdate': false,
            'fileHash': 'h1',
            'storageUri': 's3://b/b1/patch.zip',
            'createdAt': '2024-01-01T00:00:00.000Z',
          },
        ],
        'pagination': {
          'total': 1,
          'hasNextPage': false,
          'hasPreviousPage': false,
          'currentPage': 1,
          'totalPages': 1,
          'nextCursor': null,
          'previousCursor': null,
        },
      }),
      200,
    );
  }
  if (path == '/api/bundles' && method == 'POST') {
    final body = jsonDecode(request.body) as List;
    expect(body, hasLength(1));
    expect((body.first as Map)['id'], 'b1');
    return http.Response(jsonEncode({'success': true}), 201);
  }
  if (path.startsWith('/api/bundles/') && method == 'PATCH') {
    expect(request.url.path, '/api/bundles/b1');
    return http.Response(jsonEncode({'success': true}), 200);
  }
  if (path.startsWith('/api/bundles/') && method == 'DELETE') {
    expect(request.url.path, '/api/bundles/b1');
    return http.Response(jsonEncode({'success': true}), 200);
  }
  if (path.startsWith('/api/bundles/') && method == 'GET') {
    return http.Response(
      jsonEncode({
        'id': 'b1',
        'platform': 'android',
        'channel': 'production',
        'enabled': true,
        'shouldForceUpdate': false,
        'fileHash': 'h1',
        'storageUri': 's3://b/b1/patch.zip',
        'createdAt': '2024-01-01T00:00:00.000Z',
      }),
      200,
    );
  }
  if (path == '/api/fingerprint/android/fp/production/00000000-0000-0000-0000-000000000000/b1' &&
      method == 'GET') {
    return http.Response(
      jsonEncode({
        'id': 'b2',
        'shouldForceUpdate': false,
        'status': 'UPDATE',
        'fileUrl': 'https://cdn.example.com/b2/patch.zip',
        'fileHash': 'h2',
      }),
      200,
    );
  }
  if (path == '/api/upload' && method == 'POST') {
    expect(request.url.queryParameters['key'], 'b1/patch.zip');
    return http.Response(
      jsonEncode({'storageUri': 's3://b/b1/patch.zip'}),
      201,
    );
  }
  if (path == '/api/getDownloadUrl' && method == 'POST') {
    final body = jsonDecode(request.body) as Map;
    expect(body['storageUri'], 's3://b/b1/patch.zip');
    return http.Response(
      jsonEncode({'fileUrl': 'https://cdn.example.com/b1/patch.zip'}),
      200,
    );
  }
  if (path == '/api/delete' && method == 'DELETE') {
    final body = jsonDecode(request.body) as Map;
    expect(body['storageUri'], 's3://b/b1/patch.zip');
    return http.Response(jsonEncode({'success': true}), 200);
  }
  if (path == '/api/readText' && method == 'POST') {
    final body = jsonDecode(request.body) as Map;
    expect(body['storageUri'], 's3://manifest');
    return http.Response(jsonEncode({'data': 'manifest-content'}), 200);
  }
  if (path == '/api/list' && method == 'GET') {
    return http.Response(
      jsonEncode({
        'data': [
          {'key': 'b1/patch.zip', 'storageUri': 's3://b/b1/patch.zip', 'size': 3},
        ],
      }),
      200,
    );
  }
  if (path == '/api/_file' && method == 'GET') {
    return http.Response('zip', 200);
  }
  if (request.url.host == 'cdn.example.com' && method == 'GET') {
    return http.Response('zip-bytes', 200);
  }
  return http.Response(jsonEncode({'error': 'not found'}), 404);
}

void main() {
  late MockClient client;
  late StandaloneRepositoryConfig repoConfig;
  late StandaloneStorageConfig storageConfig;

  setUp(() {
    client = MockClient(_router);
    repoConfig = StandaloneRepositoryConfig(
      baseUrl: 'http://localhost',
      clientFactory: () => client,
    );
    storageConfig = StandaloneStorageConfig(
      baseUrl: 'http://localhost',
      clientFactory: () => client,
    );
  });

  group('standaloneRepository', () {
    test('getChannels', () async {
      final db = standaloneRepository(repoConfig)();
      final channels = await db.getChannels();
      expect(channels, ['production', 'staging']);
    });

    test('getBundleById', () async {
      final db = standaloneRepository(repoConfig)();
      final bundle = await db.getBundleById('b1');
      expect(bundle?.id, 'b1');
    });

    test('getBundles', () async {
      final db = standaloneRepository(repoConfig)();
      final res = await db.getBundles(
        const DatabaseBundleQueryOptions(where: null),
      );
      expect(res.data, hasLength(1));
      expect(res.data.first.id, 'b1');
    });

    test('commitBundle insert/update/delete', () async {
      final db = standaloneRepository(repoConfig)();
      await db.appendBundle(
        Bundle(
          id: 'b1',
          platform: Platform.android,
          channel: 'production',
          enabled: true,
          shouldForceUpdate: false,
          fileHash: 'h1',
          storageUri: 's3://b/b1/patch.zip',
        ),
      );
      await db.commitBundle();
      // update + delete exercise PATCH/DELETE routes via a fresh change set.
      await db.updateBundle(
        'b1',
        {'enabled': false, 'channel': 'production'},
      );
      await db.commitBundle();
      final existing = await db.getBundleById('b1');
      await db.deleteBundle(existing!);
      await db.commitBundle();
    });

    test('getUpdateInfo resolves update-available', () async {
      final db = standaloneRepository(repoConfig)();
      final info = await db.getUpdateInfo(
        FingerprintGetBundlesArgs(
          platform: Platform.android,
          bundleId: 'b1',
          fingerprintHash: 'fp',
        ),
      );
      expect(info, isNotNull);
      expect(info!.id, 'b2');
    });
  });

  group('standaloneStorage', () {
    test('upload returns storageUri', () async {
      final storage = standaloneStorage(storageConfig);
      final tmp = File('${Directory.systemTemp.path}/fp_test.zip')
        ..writeAsStringSync('zip');
      final result = await storage.profiles.node!.upload('b1/patch.zip', tmp.path);
      expect(result['storageUri'], 's3://b/b1/patch.zip');
      await tmp.delete();
    });

    test('getDownloadUrl returns fileUrl', () async {
      final storage = standaloneStorage(storageConfig);
      final result =
          await storage.profiles.runtime!.getDownloadUrl('s3://b/b1/patch.zip');
      expect(result['fileUrl'], 'https://cdn.example.com/b1/patch.zip');
    });

    test('delete succeeds', () async {
      final storage = standaloneStorage(storageConfig);
      await storage.profiles.node!.delete('s3://b/b1/patch.zip');
    });

    test('readText returns content', () async {
      final storage = standaloneStorage(storageConfig);
      final text = await storage.profiles.runtime!.readText('s3://manifest');
      expect(text, 'manifest-content');
    });

    test('downloadFile fetches bytes', () async {
      final storage = standaloneStorage(storageConfig);
      final out = '${Directory.systemTemp.path}/fp_dl.zip';
      await storage.profiles.node!.downloadFile('s3://b/b1/patch.zip', out);
      expect(File(out).readAsStringSync(), 'zip-bytes');
      await File(out).delete();
    });

    test('listObjects returns entries', () async {
      final storage = standaloneStorage(storageConfig);
      final objects = await storage.profiles.node!.listObjects();
      expect(objects, hasLength(1));
      expect(objects.first.key, 'b1/patch.zip');
    });
  });
}
