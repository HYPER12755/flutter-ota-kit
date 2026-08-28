import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:io' show Directory, File;
import 'dart:typed_data' show Uint8List;

import 'package:archive/archive.dart';
import 'package:flutter_patcher_cli/flutter_patcher_cli.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;
import 'package:test/test.dart';

// Stateful in-memory fake of the standalone (self-hosted) REST server.
class _FakeServer {
  final Map<String, Map<String, dynamic>> bundles = {};
  final Map<String, List<int>> storage = {};

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    final method = request.method;

    if (path == '/api/bundles/channels' && method == 'GET') {
      final channels = bundles.values.map((b) => b['channel'] as String).toSet().toList();
      return http.Response(jsonEncode({'data': {'channels': channels}}), 200);
    }
    if (path == '/api/bundles' && method == 'POST') {
      final list = jsonDecode(request.body) as List;
      for (final item in list) {
        final b = (item as Map).cast<String, dynamic>();
        bundles[b['id'] as String] = {...b};
      }
      return http.Response(jsonEncode({'success': true}), 201);
    }
    if (path == '/api/bundles' && method == 'GET') {
      final channel = request.url.queryParameters['channel'];
      final enabled = request.url.queryParameters['enabled'];
      var items = bundles.values.toList();
      if (channel != null) items = items.where((b) => b['channel'] == channel).toList();
      if (enabled == 'true') items = items.where((b) => b['enabled'] == true).toList();
      // Emulate the DB's default id-desc ordering (latest bundle first).
      items = items.reversed.toList();
      return http.Response(
        jsonEncode({
          'data': items,
          'pagination': {
            'total': items.length,
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
    if (path.startsWith('/api/bundles/') && method == 'PATCH') {
      final id = path.substring('/api/bundles/'.length);
      final patch = jsonDecode(request.body) as Map<String, dynamic>;
      final existing = bundles[id];
      if (existing == null) return http.Response('{"error":"not found"}', 404);
      existing.addAll(patch);
      return http.Response(jsonEncode({'success': true}), 200);
    }
    if (path.startsWith('/api/bundles/') && method == 'DELETE') {
      final id = path.substring('/api/bundles/'.length);
      bundles.remove(id);
      return http.Response(jsonEncode({'success': true}), 200);
    }
    if (path.startsWith('/api/bundles/') && method == 'GET') {
      final id = path.substring('/api/bundles/'.length);
      final b = bundles[id];
      if (b == null) return http.Response('{"error":"not found"}', 404);
      return http.Response(jsonEncode(b), 200);
    }
    if (path == '/api/upload' && method == 'POST') {
      final key = request.url.queryParameters['key']!;
      storage[key] = request.bodyBytes;
      return http.Response(jsonEncode({'storageUri': 'mem://$key'}), 201);
    }
    if (path == '/api/getDownloadUrl' && method == 'POST') {
      final uri = (jsonDecode(request.body) as Map)['storageUri'] as String;
      final key = uri.replaceFirst('mem://', '');
      return http.Response(
        jsonEncode({'fileUrl': 'http://localhost/mem/$key'}),
        200,
      );
    }
    if (path == '/api/delete' && method == 'DELETE') {
      final uri = (jsonDecode(request.body) as Map)['storageUri'] as String;
      storage.remove(uri.replaceFirst('mem://', ''));
      return http.Response(jsonEncode({'success': true}), 200);
    }
    if (request.url.host == 'localhost' && path.startsWith('/mem/')) {
      final key = path.substring('/mem/'.length);
      final bytes = storage[key];
      if (bytes == null) return http.Response('not found', 404);
      return http.Response.bytes(bytes, 200);
    }
    return http.Response(jsonEncode({'error': 'not found'}), 404);
  }
}

void main() {
  group('cli backends', () {
    test('standalone backend (self-hosted REST)', () async {
      final fake = _FakeServer();
      final client = MockClient(fake.handle);
      final config = FlutterPatcherConfig(
        provider: 'standalone',
        supabase: const SupabaseConfigJson(url: 'https://x.supabase.co'),
        standalone: StandaloneConfigJson(baseUrl: 'http://localhost'),
        channel: 'production',
        platform: 'android',
        source: './dist',
      );
      final backend = resolveBackend(
        config,
        standaloneClientFactory: () => client,
      );

      final source = Directory.systemTemp.createTempSync('fp-src-');
      File('${source.path}/app.so').writeAsStringSync('fake-libapp-bytes');
      try {
        final bundle = await deployBundle(
          backend,
          DeployOptions(
            source: source.path,
            channel: 'production',
            platform: 'android',
            message: 'first',
            targetAppVersion: '>=1.0.0',
          ),
        );
        expect(bundle.id, isNotEmpty);
        expect(bundle.storageUri, isNotEmpty);
        expect(await backend.storage.exists(bundle.storageUri), isTrue);

        final dl = File('${Directory.systemTemp.path}/fp-dl-${bundle.id}.zip');
        await backend.storage.downloadFile(bundle.storageUri, dl.path);
        expect(dl.existsSync() && await dl.length() > 0, isTrue);
        await dl.delete();

        final listed = await listBundles(backend, const ListOptions());
        expect(listed.data.where((b) => b.id == bundle.id), hasLength(1));

        final live = await getChannel(backend, 'production');
        expect(live?.id, bundle.id);

        final second = await deployBundle(
          backend,
          DeployOptions(
            source: source.path,
            channel: 'production',
            platform: 'android',
            message: 'second',
            targetAppVersion: '>=1.0.0',
          ),
        );
        await promoteBundle(backend, second.id, 'production');
        final disabled = await rollbackChannel(backend, 'production');
        expect(disabled, second.id);

        await deleteBundle(backend, bundle.id);
        final afterDelete = await listBundles(
          backend,
          const ListOptions(channel: 'production'),
        );
        expect(
          afterDelete.data.where((b) => b.id == bundle.id).isEmpty,
          isTrue,
        );
      } finally {
        source.deleteSync(recursive: true);
      }
    });

    test('standalone backend signs the deployed bundle (md5 fileHash + '
        'metadata.signature verifiable)', () async {
      final (privateB64, publicB64) = await generateEd25519KeyPair();
      final fake = _FakeServer();
      final client = MockClient(fake.handle);
      final config = FlutterPatcherConfig(
        provider: 'standalone',
        supabase: const SupabaseConfigJson(url: 'https://x.supabase.co'),
        standalone: StandaloneConfigJson(baseUrl: 'http://localhost'),
        channel: 'production',
        platform: 'android',
        source: './dist',
      );
      final backend = resolveBackend(
        config,
        standaloneClientFactory: () => client,
      );

      final source = Directory.systemTemp.createTempSync('fp-src-signed-');
      File('${source.path}/app.so').writeAsStringSync('fake-libapp-bytes');
      try {
        final bundle = await deployBundle(
          backend,
          DeployOptions(
            source: source.path,
            channel: 'production',
            platform: 'android',
            message: 'signed',
            targetAppVersion: '>=1.0.0',
            signingKeyBase64: privateB64,
          ),
        );

        // fileHash must be a plain MD5 hex (device rejects anything else).
        expect(bundle.fileHash, matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(bundle.metadata, isNotNull);
        final signature = bundle.metadata!.signature;
        expect(signature, isNotNull);
        expect(signature, isNotEmpty);

        // The signature verifies over the MD5-hex UTF-8 bytes with the SPKI
        // public key, exactly as the Android device SDK checks it.
        final verified = await ed25519Verify(
          utf8.encode(bundle.fileHash),
          signature!,
          publicB64,
        );
        expect(verified, isTrue);
      } finally {
        source.deleteSync(recursive: true);
      }
    });

    test('build + deploy uploads the real patch.zip (no nested-zip mangling)', () async {
      // 1) Build a synthetic multi-ABI APK in memory.
      final apk = Archive();
      for (final abi in const ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
        final bytes = utf8.encode('LIBAPP_$abi');
        apk.addFile(ArchiveFile('lib/$abi/libapp.so', bytes.length, bytes));
      }
      final apkDir = Directory.systemTemp.createTempSync('fp-apk-');
      final apkFile = File('${apkDir.path}/app.apk')
        ..writeAsBytesSync(Uint8List.fromList(ZipEncoder().encode(apk)));

      // 2) Pack it.
      final distDir = Directory.systemTemp.createTempSync('fp-dist-');
      await packPatch(
        apkPath: apkFile.path,
        version: '9.9.9',
        targetVersionCode: 42,
        out: distDir.path,
      );

      // 3) Deploy the packed dist/ with a signing key.
      final (privateB64, publicB64) = await generateEd25519KeyPair();
      final fake = _FakeServer();
      final client = MockClient(fake.handle);
      final config = FlutterPatcherConfig(
        provider: 'standalone',
        supabase: const SupabaseConfigJson(url: 'https://x.supabase.co'),
        standalone: StandaloneConfigJson(baseUrl: 'http://localhost'),
        channel: 'production',
        platform: 'android',
        source: distDir.path,
      );
      final backend = resolveBackend(
        config,
        standaloneClientFactory: () => client,
      );

      final bundle = await deployBundle(
        backend,
        DeployOptions(
          source: distDir.path,
          channel: 'production',
          platform: 'android',
          message: 'built',
          targetAppVersion: '>=1.0.0',
          signingKeyBase64: privateB64,
        ),
      );

      // 4) Download what the device would fetch and make sure it is the
      //    genuine patch (root manifest.json + per-ABI libapp.so), NOT a
      //    zip that nests the real patch under dist/patch.zip (the old bug).
      final dl = File('${distDir.path}/downloaded.zip');
      await backend.storage.downloadFile(bundle.storageUri, dl.path);
      final downloaded = ZipDecoder().decodeBytes(dl.readAsBytesSync());

      final names = downloaded.files.map((f) => f.name).toList();
      expect(names, contains('manifest.json'));
      expect(names, contains('lib/arm64-v8a/libapp.so'));
      expect(names, isNot(contains('dist/patch.zip')),
          reason: 'deploy must upload the real patch, not re-zip the dir');

      final manifest = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(
          downloaded.files.firstWhere((f) => f.name == 'manifest.json').content
              as List<int>,
        )) as Map,
      );
      expect(manifest['schemaVersion'], 2);
      expect((manifest['lib'] as Map).keys, hasLength(3));

      // 5) signature chain still holds on the deployed bundle.
      expect(
        await ed25519Verify(
          utf8.encode(bundle.fileHash),
          bundle.metadata!.signature!,
          publicB64,
        ),
        isTrue,
      );

      apkDir.deleteSync(recursive: true);
      distDir.deleteSync(recursive: true);
    });
  });
}
