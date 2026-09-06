import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';
import 'package:flutter_ota_kit_supabase/src/supabase_client_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Minimal in-memory Supabase mock (PostgREST + storage surfaces).
// ---------------------------------------------------------------------------

class MockResponse implements SupabaseResponseLike {
  const MockResponse({this.data, this.error, this.count});
  @override
  final Object? data;
  @override
  final Object? error;
  @override
  final int? count;
}

class MockRpcResponse implements SupabaseRpcResponse {
  const MockRpcResponse({this.data, this.error});
  @override
  final Object? data;
  @override
  final Object? error;
}

class MockUploadResult implements SupabaseUploadResult {
  const MockUploadResult({this.data, this.error});
  @override
  final Object? data;
  @override
  final Object? error;
}

class MockSignedUrlResult implements SupabaseSignedUrlResult {
  const MockSignedUrlResult({this.signedUrl, this.error});
  @override
  final String? signedUrl;
  @override
  final Object? error;
}

class MockSignedUrlListResult implements SupabaseSignedUrlListResult {
  const MockSignedUrlListResult({this.data, this.error});
  @override
  final List<SupabaseSignedUrlResult>? data;
  @override
  final Object? error;
}

class MockDownloadResult implements SupabaseDownloadResult {
  const MockDownloadResult({this.data, this.error, this.message});
  @override
  final List<int>? data;
  @override
  final Object? error;
  @override
  final String? message;
}

class MockRemoveResult implements SupabaseRemoveResult {
  const MockRemoveResult({this.data, this.error, this.message});
  @override
  final Object? data;
  @override
  final Object? error;
  @override
  final String? message;
}

class MockExistsResult implements SupabaseExistsResult {
  const MockExistsResult({this.data, this.error, this.message});
  @override
  final bool? data;
  @override
  final Object? error;
  @override
  final String? message;
}

class MockStorageObject implements SupabaseStorageObject {
  MockStorageObject(this.key, this.size);
  @override
  final String key;
  @override
  final int size;
  @override
  @override
  final String? lastModifiedAt = null;
}

class MockListResult implements SupabaseListResult {
  const MockListResult({this.data, this.error});
  @override
  final List<SupabaseStorageObject>? data;
  @override
  final Object? error;
}

class MockBuilder
    implements SupabaseQueryBuilderLike, SupabaseFilterBuilderLike {
  MockBuilder(this._client, this._table);

  final MockSupabaseClient _client;
  final String _table;

  String _op = 'select';
  final Map<String, Object?> _eq = {};
  final Map<String, List<Object?>> _in = {};
  bool _single = false;
  bool _head = false;
  bool _count = false;
  String _order = 'id';
  bool _ascending = false;

  @override
  SupabaseFilterBuilderLike select(String columns, {bool? count, bool? head}) =>
      _asSelect(count: count, head: head);

  MockBuilder _asSelect({bool? count, bool? head}) {
    _op = 'select';
    _count = count ?? false;
    _head = head ?? false;
    return this;
  }

  @override
  SupabaseFilterBuilderLike delete() {
    _op = 'delete';
    return this;
  }

  Map<String, Object?> _toRow(dynamic raw) =>
      raw is Map ? raw.cast<String, Object?>() : (raw as dynamic).toJson();

  @override
  Future<dynamic> upsert(dynamic values, {String? onConflict}) {
    final rows = (values is List) ? values.cast<Object?>() : [values];
    for (final raw in rows) {
      final row = _toRow(raw);
      if (_table == 'bundles') {
        _client._bundles[row['id'] as String] = row;
      } else if (_table == 'bundle_patches') {
        _client._patches[row['id'] as String] = row;
      }
    }
    return Future.value(const MockResponse(data: {}, error: null));
  }

  @override
  SupabaseFilterBuilderLike eq(String column, Object? value) {
    _eq[column] = value;
    return this;
  }

  @override
  SupabaseFilterBuilderLike in_(String column, List<Object?> values) {
    _in[column] = values;
    return this;
  }

  @override
  SupabaseFilterBuilderLike gt(String column, Object? value) => this;
  @override
  SupabaseFilterBuilderLike gte(String column, Object? value) => this;
  @override
  SupabaseFilterBuilderLike lt(String column, Object? value) => this;
  @override
  SupabaseFilterBuilderLike lte(String column, Object? value) => this;
  @override
  SupabaseFilterBuilderLike isFilter(String column, Object? value) => this;
  @override
  SupabaseFilterBuilderLike not(
    String column,
    String operator,
    Object? value,
  ) => this;
  @override
  SupabaseFilterBuilderLike order(String column, {bool? ascending}) {
    _order = column;
    _ascending = ascending ?? false;
    return this;
  }

  @override
  SupabaseFilterBuilderLike limit(int value) => this;
  @override
  SupabaseFilterBuilderLike range(int from, int to) => this;
  @override
  SupabaseFilterBuilderLike single() {
    _single = true;
    return this;
  }

  @override
  Future<SupabaseResponseLike> execute() async {
    if (_op == 'delete') {
      if (_table == 'bundles' && _eq['id'] != null) {
        _client._bundles.remove(_eq['id']);
      } else if (_table == 'bundle_patches' && _eq['bundle_id'] != null) {
        _client._patches.removeWhere(
          (k, v) => v['bundle_id'] == _eq['bundle_id'],
        );
      }
      return const MockResponse(data: {}, error: null);
    }
    // select
    if (_head && _count) {
      final total = _table == 'bundles'
          ? _client._bundles.length
          : _client._patches.length;
      return MockResponse(data: const [], count: total, error: null);
    }
    if (_table == 'bundle_patches') {
      var rows = _client._patches.values.toList();
      if (_in['bundle_id'] != null) {
        rows = rows
            .where((r) => _in['bundle_id']!.contains(r['bundle_id']))
            .toList();
      }
      return MockResponse(data: rows, error: null);
    }
    var rows = _client._bundles.values.toList();
    if (_eq['id'] != null) {
      rows = rows.where((r) => r['id'] == _eq['id']).toList();
    }
    if (_table == 'bundles' && _order == 'id') {
      rows.sort(
        (a, b) =>
            (_ascending ? 1 : -1) *
            (a['id'] as String).compareTo(b['id'] as String),
      );
    }
    if (_single) {
      return MockResponse(data: rows.isEmpty ? null : rows.first, error: null);
    }
    return MockResponse(data: rows, error: null);
  }
}

class MockBucket implements SupabaseStorageBucketLike {
  MockBucket(this._client, this._bucket);
  final MockSupabaseClient _client;
  final String _bucket;

  @override
  Future<SupabaseSignedUrlResult> createSignedUrl(
    String path,
    int expiresIn,
  ) async => MockSignedUrlResult(
    signedUrl: 'https://signed/$_bucket/$path',
    error: null,
  );

  @override
  Future<SupabaseSignedUrlListResult> createSignedUrls(
    List<String> paths,
    int expiresIn,
  ) async => MockSignedUrlListResult(
    data: paths
        .map(
          (p) => MockSignedUrlResult(signedUrl: 'https://signed/$_bucket/$p'),
        )
        .toList(),
    error: null,
  );

  @override
  Future<SupabaseUploadResult> upload(
    String path,
    List<int> fileBytes, {
    String? contentType,
    String? cacheControl,
  }) async {
    _client._storage[path] = Uint8List.fromList(fileBytes);
    return MockUploadResult(data: {'Key': path}, error: null);
  }

  @override
  Future<SupabaseRemoveResult> remove(List<String> paths) async {
    for (final p in paths) {
      _client._storage.remove(p);
    }
    return MockRemoveResult(data: paths, error: null);
  }

  @override
  Future<SupabaseExistsResult> exists(String path) async =>
      MockExistsResult(data: _client._storage.containsKey(path), error: null);

  @override
  Future<SupabaseDownloadResult> download(String path) async =>
      MockDownloadResult(data: _client._storage[path], error: null);

  @override
  Future<SupabaseListResult> list([String? prefix]) async {
    final data = _client._storage.keys
        .where((k) => prefix == null || k.startsWith(prefix))
        .map((k) => MockStorageObject(k, _client._storage[k]!.length))
        .toList();
    return MockListResult(data: data, error: null);
  }
}

class MockStorageClient implements SupabaseStorageClientLike {
  MockStorageClient(this._client);
  final MockSupabaseClient _client;
  @override
  SupabaseStorageBucketLike from(String bucket) => MockBucket(_client, bucket);
}

class MockSupabaseClient implements SupabaseClientLike {
  final Map<String, Map<String, Object?>> _bundles = {};
  final Map<String, Map<String, Object?>> _patches = {};
  final Map<String, List<int>> _storage = {};

  @override
  SupabaseQueryBuilderLike from(String table) => MockBuilder(this, table);

  @override
  SupabaseStorageClientLike get storage => MockStorageClient(this);

  @override
  Future<SupabaseRpcResponse> rpc(
    String functionName, {
    Map<String, dynamic>? params,
  }) async {
    if (functionName == 'get_channels') {
      return const MockRpcResponse(
        data: [
          {'channel': 'production'},
          {'channel': 'staging'},
        ],
        error: null,
      );
    }
    return const MockRpcResponse(data: [], error: null);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

FlutterPatcherConfig _config() => FlutterPatcherConfig(
  provider: 'supabase',
  supabase: SupabaseConfigJson(
    url: 'https://demo.supabase.co',
    serviceRoleKey: 'service-role-key',
    bucket: 'bundles',
  ),
  channel: 'production',
  platform: 'android',
  source: './dist',
);

Backend _backend(MockSupabaseClient mock) =>
    resolveBackend(_config(), supabaseClientFactory: (url, key) => mock);

void main() {
  group('flutter_ota_kit_cli', () {
    late MockSupabaseClient mock;
    late Backend backend;

    setUp(() {
      mock = MockSupabaseClient();
      backend = _backend(mock);
    });

    test('deploy uploads a bundle and registers it', () async {
      final dir = await Directory.systemTemp.createTemp('src');
      try {
        await File(p.join(dir.path, 'main.dart')).writeAsString('print(1);');
        final bundle = await deployBundle(
          backend,
          DeployOptions(
            source: dir.path,
            channel: 'production',
            platform: 'android',
            targetAppVersion: '1.0.0',
          ),
        );
        expect(bundle.enabled, isTrue);
        expect(mock._bundles.containsKey(bundle.id), isTrue);
        expect(mock._storage.isNotEmpty, isTrue);
        expect(bundle.storageUri, contains('supabase-storage://'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('bundle list returns deployed bundle', () async {
      final dir = await Directory.systemTemp.createTemp('src');
      try {
        await File(p.join(dir.path, 'a.txt')).writeAsString('x');
        final deployed = await deployBundle(
          backend,
          DeployOptions(
            source: dir.path,
            channel: 'production',
            platform: 'android',
            targetAppVersion: '1.0.0',
          ),
        );
        final res = await listBundles(
          backend,
          ListOptions(channel: 'production'),
        );
        expect(res.data.map((b) => b.id), contains(deployed.id));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('channel list returns seeded channels', () async {
      final channels = await listChannels(backend);
      expect(channels, containsAll(['production', 'staging']));
    });

    test('bundle delete removes the bundle', () async {
      final dir = await Directory.systemTemp.createTemp('src');
      try {
        await File(p.join(dir.path, 'a.txt')).writeAsString('x');
        final deployed = await deployBundle(
          backend,
          DeployOptions(
            source: dir.path,
            channel: 'production',
            platform: 'android',
            targetAppVersion: '1.0.0',
          ),
        );
        await deleteBundle(backend, deployed.id);
        expect(mock._bundles.containsKey(deployed.id), isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('rollback disables the latest enabled bundle on a channel', () async {
      final dir = await Directory.systemTemp.createTemp('src');
      try {
        await File(p.join(dir.path, 'a.txt')).writeAsString('x');
        final first = await deployBundle(
          backend,
          DeployOptions(
            source: dir.path,
            channel: 'production',
            platform: 'android',
            targetAppVersion: '1.0.0',
          ),
        );
        final second = await deployBundle(
          backend,
          DeployOptions(
            source: dir.path,
            channel: 'production',
            platform: 'android',
            targetAppVersion: '2.0.0',
          ),
        );
        final disabled = await rollbackChannel(backend, 'production');
        expect(disabled, equals(second.id));
        expect(mock._bundles[first.id]!['enabled'], isTrue);
        expect(mock._bundles[second.id]!['enabled'], isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('promote assigns a bundle to a channel', () async {
      final dir = await Directory.systemTemp.createTemp('src');
      try {
        await File(p.join(dir.path, 'a.txt')).writeAsString('x');
        final b = await deployBundle(
          backend,
          DeployOptions(
            source: dir.path,
            channel: 'production',
            platform: 'android',
            targetAppVersion: '1.0.0',
          ),
        );
        await promoteBundle(backend, b.id, 'staging');
        expect(mock._bundles[b.id]!['channel'], equals('staging'));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
