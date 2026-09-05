import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show Bundle, BundleMetadata, Platform;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';
import 'package:test/test.dart';

void main() {
  group('paginateBundles', () {
    List<Bundle> makeBundles(int count) => List.generate(
      count,
      (i) => _testBundle(id: 'b-${i.toString().padLeft(3, '0')}'),
    );

    test('offset-based first page', () {
      final result = paginateBundles(
        bundles: makeBundles(25),
        limit: 10,
        offset: 0,
      );
      expect(result.data.length, 10);
      expect(result.pagination.total, 25);
      expect(result.pagination.hasNextPage, isTrue);
      expect(result.pagination.hasPreviousPage, isFalse);
      expect(result.pagination.currentPage, 1);
      expect(result.pagination.nextCursor, isNotNull);
      expect(result.pagination.previousCursor, isNull);
    });

    test('offset-based last page', () {
      final result = paginateBundles(
        bundles: makeBundles(25),
        limit: 10,
        offset: 20,
      );
      expect(result.data.length, 5);
      expect(result.pagination.hasNextPage, isFalse);
      expect(result.pagination.hasPreviousPage, isTrue);
    });

    test('cursor-based after', () {
      final result = paginateBundles(
        bundles: makeBundles(10),
        limit: 3,
        cursor: const DatabaseBundleCursor(after: 'b-004'),
      );
      // Sorted desc: b-009..b-000. After b-004 (id < 'b-004'): b-003, b-002, b-001, b-000
      expect(result.data.length, 3);
      expect(result.data.first.id, 'b-003');
      expect(result.data.last.id, 'b-001');
    });

    test('cursor-based before', () {
      final result = paginateBundles(
        bundles: makeBundles(10),
        limit: 3,
        cursor: const DatabaseBundleCursor(before: 'b-005'),
      );
      // Before b-005 in desc: candidates id > b-005 = [b-009, b-008, b-007, b-006]
      // Take last 3 (closest to cursor): b-008, b-007, b-006
      expect(result.data.length, 3);
      expect(result.data.first.id, 'b-008');
      expect(result.data.last.id, 'b-006');
    });

    test('empty result preserves cursor', () {
      final result = paginateBundles(
        bundles: makeBundles(5),
        limit: 10,
        cursor: const DatabaseBundleCursor(after: 'b-000'),
      );
      // Desc sorted: b-004, b-003, b-002, b-001, b-000
      // after 'b-000': nothing has id < 'b-000' → empty, previousCursor preserved
      expect(result.data, isEmpty);
      expect(result.pagination.previousCursor, 'b-000');
    });
  });

  group('filterCompatibleAppVersions', () {
    test('filters and sorts descending', () {
      final result = filterCompatibleAppVersions([
        '^1.0.0',
        '^2.0.0',
        '^0.5.0',
      ], '1.3.0');
      expect(result, ['^1.0.0']);
    });

    test('multiple compatible versions sorted desc', () {
      final result = filterCompatibleAppVersions([
        '>=1.0.0',
        '>=1.2.0',
        '>=2.0.0',
      ], '1.5.0');
      expect(result, ['>=1.2.0', '>=1.0.0']);
    });
  });

  group('parseStorageUri', () {
    test('parses supabase-storage URI', () {
      final result = parseStorageUri(
        'supabase-storage://bucket/path/to/file.zip',
        'supabase-storage',
      );
      expect(result.protocol, 'supabase-storage');
      expect(result.bucket, 'bucket');
      expect(result.key, 'path/to/file.zip');
    });

    test('parses s3 URI', () {
      final result = parseStorageUri('s3://my-bucket/key.zip', 's3');
      expect(result.bucket, 'my-bucket');
      expect(result.key, 'key.zip');
    });

    test('decodes percent-encoded keys', () {
      final result = parseStorageUri(
        'supabase-storage://bucket/path%20with%20spaces/file.zip',
        'supabase-storage',
      );
      expect(result.key, 'path with spaces/file.zip');
    });

    test('throws on wrong protocol', () {
      expect(
        () => parseStorageUri('s3://bucket/key', 'supabase-storage'),
        throwsFormatException,
      );
    });
  });

  group('contentAddressedAssets', () {
    test('builds sha256 path with extension', () {
      final path = getContentAddressedAssetStoragePath(
        assetPath: 'index.android.bundle',
        fileHash: 'abcdef1234567890',
      );
      expect(path, 'sha256/ab/abcdef1234567890.bundle');
    });

    test('preserves .br extension', () {
      final path = getContentAddressedAssetStoragePath(
        assetPath: 'index.android.bundle.br',
        fileHash: 'abcdef1234567890',
      );
      expect(path, 'sha256/ab/abcdef1234567890.br');
    });

    test('handles no extension', () {
      final path = getContentAddressedAssetStoragePath(
        assetPath: 'manifest',
        fileHash: 'abcdef1234567890',
      );
      expect(path, 'sha256/ab/abcdef1234567890');
    });
  });

  group('compressionFormat', () {
    test('detects zip', () {
      expect(
        detectCompressionFormat('bundle.zip').format,
        CompressionFormat.zip,
      );
    });

    test('detects tar.br', () {
      expect(
        detectCompressionFormat('bundle.tar.br').format,
        CompressionFormat.tarBr,
      );
    });

    test('detects tar.gz', () {
      expect(
        detectCompressionFormat('bundle.tar.gz').format,
        CompressionFormat.tarGz,
      );
    });

    test('defaults to zip', () {
      expect(
        detectCompressionFormat('bundle.xyz').format,
        CompressionFormat.zip,
      );
    });

    test('getContentType returns mime type for zip', () {
      expect(getContentType('bundle.zip'), 'application/zip');
    });
  });

  group('storageProfile', () {
    test('isNodeStoragePlugin checks profiles.node', () {
      final plugin = _DummyStoragePlugin(node: true, runtime: false);
      expect(isNodeStoragePlugin(plugin), isTrue);
      expect(isRuntimeStoragePlugin(plugin), isFalse);
    });

    test('isRuntimeStoragePlugin checks profiles.runtime', () {
      final plugin = _DummyStoragePlugin(node: false, runtime: true);
      expect(isNodeStoragePlugin(plugin), isFalse);
      expect(isRuntimeStoragePlugin(plugin), isTrue);
    });

    test('assertNodeStoragePlugin throws if missing', () {
      final plugin = _DummyStoragePlugin(node: false, runtime: true);
      expect(() => assertNodeStoragePlugin(plugin), throwsStateError);
    });
  });

  group('createStorageKeyBuilder', () {
    test('with base path', () {
      final getKey = createStorageKeyBuilder('bundles');
      expect(getKey('v1', 'patch.zip'), 'bundles/v1/patch.zip');
    });

    test('without base path', () {
      final getKey = createStorageKeyBuilder(null);
      expect(getKey('v1', 'file.zip'), 'v1/file.zip');
    });
  });
}

Bundle _testBundle({String id = 'test-bundle-id'}) {
  return Bundle(
    id: id,
    channel: 'production',
    platform: Platform.android,
    enabled: true,
    shouldForceUpdate: false,
    fileHash: 'abc123',
    gitCommitHash: null,
    message: null,
    targetAppVersion: '1.0.0',
    fingerprintHash: null,
    storageUri: 'supabase-storage://bucket/path',
    metadata: const BundleMetadata(),
    patches: const [],
    rolloutCohortCount: 1000,
    targetCohorts: null,
  );
}

class _DummyStoragePlugin extends StoragePlugin {
  _DummyStoragePlugin({required bool node, required bool runtime})
    : _node = node,
      _runtime = runtime;

  final bool _node;
  final bool _runtime;

  @override
  String get name => 'dummy';

  @override
  String get supportedProtocol => 'dummy';

  @override
  StoragePluginProfiles get profiles => StoragePluginProfiles(
    node: _node ? _DummyNodeStorageProfile() : null,
    runtime: _runtime ? _DummyRuntimeStorageProfile() : null,
  );
}

class _DummyNodeStorageProfile extends NodeStorageProfile {
  @override
  Future<Map<String, String>> upload(String key, String filePath) async => {};
  @override
  Future<bool> exists(String storageUri) async => false;
  @override
  Future<void> delete(String storageUri) async {}
  @override
  Future<void> downloadFile(String storageUri, String filePath) async {}
  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async => [];
  @override
  Future<void> deleteObjects(List<String> keys) async {}
}

class _DummyRuntimeStorageProfile extends RuntimeStorageProfile {
  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async => {};
  @override
  Future<String?> readText(String storageUri) async => null;
}
