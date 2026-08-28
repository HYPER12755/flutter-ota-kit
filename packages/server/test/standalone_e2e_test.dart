import 'dart:io' show Directory, File, HttpServer;

import 'package:flutter_patcher_cloudflare/flutter_patcher_cloudflare.dart'
    show d1Database;
import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show Bundle, Platform;
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show
        DatabaseBundleQueryOptions,
        NodeStorageProfile,
        RuntimeStorageProfile,
        StorageObject,
        StoragePlugin,
        StoragePluginProfiles;
import 'package:flutter_patcher_server/flutter_patcher_server.dart'
    show createHotUpdater, HandlerRoutes, ServerOptions;
import 'package:flutter_patcher_standalone/flutter_patcher_standalone.dart'
    show
        StandaloneRepositoryConfig,
        StandaloneStorageConfig,
        standaloneRepository,
        standaloneStorage;
import 'package:shelf/shelf_io.dart' show serve;
import 'package:test/test.dart';

import '../../../plugins/cloudflare/test/mock_d1_client.dart' show Store, mockConfig;

/// In-memory storage that stores bytes and resolves a server-served URL.
class _MemStorage extends StoragePlugin {
  _MemStorage(this._baseUrl);

  String _baseUrl;
  final Map<String, List<int>> _store = {};

  @override
  String get name => 'memStorage';
  @override
  String get supportedProtocol => 'mem';

  @override
  StoragePluginProfiles get profiles => StoragePluginProfiles(
        node: _Node(this),
        runtime: _Runtime(this),
      );

  String _strip(String uri) => uri.replaceFirst('mem://bucket/', '');

  String downloadUrlFor(String storageUri) =>
      '$_baseUrl/api/_file?uri=${Uri.encodeComponent(storageUri)}';
}

class _Node implements NodeStorageProfile {
  _Node(this._owner);
  final _MemStorage _owner;

  @override
  Future<Map<String, String>> upload(String key, String filePath) async {
    _owner._store[key] = await File(filePath).readAsBytes();
    return {'storageUri': 'mem://bucket/$key'};
  }

  @override
  Future<bool> exists(String storageUri) async =>
      _owner._store.containsKey(_owner._strip(storageUri));

  @override
  Future<void> delete(String storageUri) async =>
      _owner._store.remove(_owner._strip(storageUri));

  @override
  Future<void> downloadFile(String storageUri, String filePath) async {
    final bytes = _owner._store[_owner._strip(storageUri)];
    if (bytes == null) throw StateError('object not found: $storageUri');
    await File(filePath).writeAsBytes(bytes);
  }

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async =>
      _owner._store.entries
          .where((e) => prefix == null || e.key.startsWith(prefix))
          .map((e) => StorageObject(
                key: e.key,
                storageUri: 'mem://bucket/${e.key}',
                size: e.value.length,
              ))
          .toList();

  @override
  Future<void> deleteObjects(List<String> keys) async =>
      keys.forEach(_owner._store.remove);
}

class _Runtime implements RuntimeStorageProfile {
  _Runtime(this._owner);
  final _MemStorage _owner;

  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async => {
        'fileUrl': _owner.downloadUrlFor(storageUri),
      };

  @override
  Future<String?> readText(String storageUri) async {
    final bytes = _owner._store[_owner._strip(storageUri)];
    return bytes == null ? null : String.fromCharCodes(bytes);
  }
}

void main() {
  late Store store;
  late _MemStorage storage;
  late String baseUrl;
  late StandaloneRepositoryConfig repoConfig;
  late StandaloneStorageConfig storageConfig;
  late HttpServer server;

  setUpAll(() async {
    store = Store();
    final database = d1Database(mockConfig(store))();
    storage = _MemStorage('http://placeholder');
    final handler = createHotUpdater(
      ServerOptions(
        database: database,
        storages: [storage],
        routes: const HandlerRoutes(
          updateCheck: true,
          bundles: true,
          storage: true,
        ),
      ),
    ).handler;
    server = await serve(handler, 'localhost', 0);
    baseUrl = 'http://localhost:${server.port}';
    storage._baseUrl = baseUrl;
    repoConfig = StandaloneRepositoryConfig(baseUrl: baseUrl);
    storageConfig = StandaloneStorageConfig(baseUrl: baseUrl);
  });

  tearDownAll(() => server.close());

  test('standalone client talks to the self-hosted server end-to-end', () async {
    final db = standaloneRepository(repoConfig)();
    final st = standaloneStorage(storageConfig);

    // 1. Deploy: register a bundle + upload its artifact.
    const bundleId = 'b-standalone-1';
    await db.appendBundle(
      Bundle(
        id: bundleId,
        platform: Platform.android,
        channel: 'production',
        enabled: true,
        shouldForceUpdate: false,
        fileHash: 'h-standalone',
        storageUri: 'mem://bucket/$bundleId/patch.zip',
      ),
    );
    await db.commitBundle();

    final tmp = File('${Directory.systemTemp.path}/fp_e2e_$bundleId.zip')
      ..writeAsStringSync('bundle-bytes');
    final uploaded =
        await st.profiles.node!.upload('$bundleId/patch.zip', tmp.path);
    expect(uploaded['storageUri'], 'mem://bucket/$bundleId/patch.zip');
    await tmp.delete();

    // 2. List bundles + channels through the same client.
    final bundles = await db.getBundles(const DatabaseBundleQueryOptions());
    expect(bundles.data.any((b) => b.id == bundleId), isTrue);

    final channels = await db.getChannels();
    expect(channels, contains('production'));

    // 3. Download the artifact back through the server-served URL.
    final fileUrl =
        (await st.profiles.runtime!.getDownloadUrl(uploaded['storageUri']!))
            ['fileUrl'];
    expect(fileUrl, contains('/api/_file?uri='));

    final dl = '${Directory.systemTemp.path}/fp_e2e_dl_$bundleId.zip';
    await st.profiles.node!.downloadFile(uploaded['storageUri']!, dl);
    expect(File(dl).readAsStringSync(), 'bundle-bytes');
    await File(dl).delete();

    // 4. Roll the bundle back (disable) via the client.
    final existing = await db.getBundleById(bundleId);
    expect(existing, isNotNull);
    await db.updateBundle(bundleId, {'enabled': false});
    await db.commitBundle();
    final after = await db.getBundleById(bundleId);
    expect(after!.enabled, isFalse);
  });
}
