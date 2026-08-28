import 'dart:io';

import 'package:flutter_patcher_core/flutter_patcher_core.dart' hide Platform;
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show
        AbstractDatabasePlugin,
        BundleChange,
        createDatabasePlugin,
        DatabaseBundleQueryOptions,
        DatabaseBundleQueryWhere,
        NodeStorageProfile,
        Paginated,
        PaginationInfo,
        RuntimeStorageProfile,
        StorageObject,
        StoragePlugin,
        StoragePluginProfiles;
import 'package:flutter_patcher_server/flutter_patcher_server.dart'
    show createHotUpdater, HandlerRoutes, ServerOptions;
import 'package:shelf/shelf.dart' as shelf;

/// Minimal in-memory database plugin (demo / local dev only).
class _MemDatabase extends AbstractDatabasePlugin {
  final Map<String, Bundle> _bundles = {};

  String get name => 'memDatabase';

  @override
  Future<List<String>> getChannels() =>
      Future.value(_bundles.values.map((b) => b.channel).toSet().toList());

  @override
  Future<Bundle?> getBundleById(String bundleId) =>
      Future.value(_bundles[bundleId]);

  @override
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args) async {
    final candidates = _bundles.values.where((b) =>
        b.enabled &&
        b.channel == args.channel &&
        b.platform == args.platform &&
        (args is AppVersionGetBundlesArgs
            ? b.targetAppVersion == args.appVersion
            : b.fingerprintHash ==
                (args as FingerprintGetBundlesArgs).fingerprintHash));
    final best = candidates.isEmpty
        ? null
        : candidates.reduce((a, b) => a.id.compareTo(b.id) > 0 ? a : b);
    if (best == null) return null;
    return UpdateInfo(
      id: best.id,
      shouldForceUpdate: best.shouldForceUpdate,
      message: best.message,
      status: UpdateStatus.update,
      storageUri: best.storageUri,
      fileHash: best.fileHash,
    );
  }

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) async {
    final where = options.where ?? const DatabaseBundleQueryWhere();
    var list = _bundles.values.where((b) {
      if (where.channel != null && b.channel != where.channel) return false;
      if (where.platform != null && b.platform != where.platform) return false;
      if (where.enabled != null && b.enabled != where.enabled) return false;
      return true;
    }).toList();
    list.sort((a, b) => b.id.compareTo(a.id));
    final total = list.length;
    final start = ((options.page ?? 1) - 1) * options.limit;
    final end = start + options.limit;
    final pageItems = list.sublist(
      start.clamp(0, total),
      end.clamp(0, total),
    );
    return Paginated(
      data: pageItems,
      pagination: PaginationInfo(
        total: total,
        hasNextPage: end < total,
        hasPreviousPage: start > 0,
        currentPage: options.page ?? 1,
        totalPages: (total / options.limit).ceil(),
      ),
    );
  }

  Future<void> appendBundle(Bundle bundle) async => _bundles[bundle.id] = bundle;

  Future<void> updateBundle(
    String targetBundleId,
    Map<String, Object?> newBundle,
  ) async {
    final b = _bundles[targetBundleId];
    if (b != null) {
      _bundles[targetBundleId] = _applyPatch(b, newBundle);
    }
  }

  Future<void> deleteBundle(Bundle deleteBundle) async =>
      _bundles.remove(deleteBundle.id);

  @override
  Future<void> onUnmount() async {}

  @override
  bool get supportsCursorPagination => false;

  @override
  Future<void> commitBundle({
    required List<BundleChange> changedSets,
  }) async {
    for (final op in changedSets) {
      // In-memory demo: changes are already applied via append/update/delete.
      if (op.operation.name == 'delete') _bundles.remove(op.data.id);
    }
  }
}

Bundle _applyPatch(Bundle b, Map<String, Object?> patch) =>
    Bundle.fromJson({...b.toJson(), ...patch});

/// Minimal in-memory storage plugin (demo / local dev only).
class _MemStorage extends StoragePlugin {
  _MemStorage(this._store);

  final Map<String, List<int>> _store;

  @override
  String get name => 'memStorage';

  @override
  String get supportedProtocol => 'mem';

  @override
  StoragePluginProfiles get profiles => StoragePluginProfiles(
        node: _MemNode(_store),
        runtime: _MemRuntime(_store),
      );
}

class _MemNode implements NodeStorageProfile {
  _MemNode(this._store);
  final Map<String, List<int>> _store;

  @override
  Future<Map<String, String>> upload(String key, String filePath) async {
    _store[key] = File(filePath).readAsBytesSync();
    return {'storageUri': 'mem://bucket/$key'};
  }

  @override
  Future<bool> exists(String storageUri) async =>
      _store.containsKey(_strip(storageUri));

  @override
  Future<void> delete(String storageUri) async => _store.remove(_strip(storageUri));

  @override
  Future<void> downloadFile(String storageUri, String filePath) async =>
      File(filePath).writeAsBytesSync(_store[_strip(storageUri)] ?? []);

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async =>
      _store.keys
          .where((k) => prefix == null || k.startsWith(prefix))
          .map(
            (k) => StorageObject(
              key: k,
              storageUri: 'mem://bucket/$k',
              size: 0,
            ),
          )
          .toList();

  @override
  Future<void> deleteObjects(List<String> keys) async {
    for (final k in keys) {
      _store.remove(k);
    }
  }

  String _strip(String uri) => uri.replaceFirst('mem://bucket/', '');
}

class _MemRuntime implements RuntimeStorageProfile {
  _MemRuntime(this._store);
  final Map<String, List<int>> _store;

  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async =>
      {'fileUrl': 'https://cdn.example.com/${_strip(storageUri)}'};

  @override
  Future<String?> readText(String storageUri) async {
    final bytes = _store[_strip(storageUri)];
    if (bytes == null) return null;
    return String.fromCharCodes(bytes);
  }

  String _strip(String uri) => uri.replaceFirst('mem://bucket/', '');
}

class _MemConfig {
  const _MemConfig();
}

void main(List<String> args) async {
  final store = <String, List<int>>{};
  final db = createDatabasePlugin<Object>(
    name: 'memDatabase',
    factory: (_) => _MemDatabase(),
  )(const _MemConfig())();
  final storage = _MemStorage(store);

  final api = createHotUpdater(
    ServerOptions(
      database: db,
      storages: [storage],
      basePath: '/api',
      routes: const HandlerRoutes(updateCheck: true, bundles: true),
    ),
  );

  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler(api.handler);

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  // ignore: avoid_print
  print('flutter_patcher server listening on http://${server.address.host}:$port'
      ' (basePath: ${api.basePath}, adapter: ${api.adapterName})');

  await for (final req in server) {
    try {
      final body = await req.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      final headers = <String, String>{};
      req.headers.forEach((name, values) {
        if (values.isNotEmpty) headers[name] = values.last;
      });
      final request = shelf.Request(
        req.method,
        req.uri,
        headers: headers,
        body: body,
      );
      final response = await handler(request);
      req.response.statusCode = response.statusCode;
      response.headers.forEach((name, value) {
        req.response.headers.set(name, value);
      });
      await req.response.addStream(response.read());
      await req.response.close();
    } catch (e) {
      req.response
        ..statusCode = 500
        ..writeln('Internal server error: $e');
      await req.response.close();
    }
  }
}
