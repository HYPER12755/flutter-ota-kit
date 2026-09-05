import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show Bundle, BundleMetadata, Platform;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';
import 'package:test/test.dart';

void main() {
  group('calculatePagination', () {
    test('empty total', () {
      final p = calculatePagination(0, limit: 10, offset: 0);
      expect(p.total, 0);
      expect(p.hasNextPage, isFalse);
      expect(p.hasPreviousPage, isFalse);
      expect(p.currentPage, 1);
      expect(p.totalPages, 0);
    });

    test('first page', () {
      final p = calculatePagination(25, limit: 10, offset: 0);
      expect(p.total, 25);
      expect(p.hasNextPage, isTrue);
      expect(p.hasPreviousPage, isFalse);
      expect(p.currentPage, 1);
      expect(p.totalPages, 3);
    });

    test('middle page', () {
      final p = calculatePagination(25, limit: 10, offset: 10);
      expect(p.currentPage, 2);
      expect(p.hasNextPage, isTrue);
      expect(p.hasPreviousPage, isTrue);
    });

    test('last page', () {
      final p = calculatePagination(25, limit: 10, offset: 20);
      expect(p.currentPage, 3);
      expect(p.hasNextPage, isFalse);
      expect(p.hasPreviousPage, isTrue);
    });
  });

  group('bundleIdMatchesFilter', () {
    test('null filter matches all', () {
      expect(bundleIdMatchesFilter('abc', null), isTrue);
    });

    test('eq match', () {
      expect(
        bundleIdMatchesFilter('abc', const DatabaseBundleIdFilter(eq: 'abc')),
        isTrue,
      );
      expect(
        bundleIdMatchesFilter('abc', const DatabaseBundleIdFilter(eq: 'def')),
        isFalse,
      );
    });

    test('gt match', () {
      expect(
        bundleIdMatchesFilter('b', const DatabaseBundleIdFilter(gt: 'a')),
        isTrue,
      );
      expect(
        bundleIdMatchesFilter('a', const DatabaseBundleIdFilter(gt: 'b')),
        isFalse,
      );
    });

    test('in match', () {
      expect(
        bundleIdMatchesFilter(
          'a',
          const DatabaseBundleIdFilter(ins: ['a', 'b']),
        ),
        isTrue,
      );
      expect(
        bundleIdMatchesFilter(
          'c',
          const DatabaseBundleIdFilter(ins: ['a', 'b']),
        ),
        isFalse,
      );
    });

    test('combined filters', () {
      final f = DatabaseBundleIdFilter(gte: 'a', lte: 'z');
      expect(bundleIdMatchesFilter('m', f), isTrue);
      expect(bundleIdMatchesFilter('0', f), isFalse);
    });
  });

  group('bundleMatchesQueryWhere', () {
    test('null where matches all', () {
      final bundle = _testBundle(channel: 'prod');
      expect(bundleMatchesQueryWhere(bundle, null), isTrue);
    });

    test('filters by channel', () {
      final bundle = _testBundle(channel: 'prod');
      expect(
        bundleMatchesQueryWhere(
          bundle,
          const DatabaseBundleQueryWhere(channel: 'prod'),
        ),
        isTrue,
      );
      expect(
        bundleMatchesQueryWhere(
          bundle,
          const DatabaseBundleQueryWhere(channel: 'dev'),
        ),
        isFalse,
      );
    });

    test('filters by enabled', () {
      final bundle = _testBundle(enabled: true);
      expect(
        bundleMatchesQueryWhere(
          bundle,
          const DatabaseBundleQueryWhere(enabled: true),
        ),
        isTrue,
      );
      expect(
        bundleMatchesQueryWhere(
          bundle,
          const DatabaseBundleQueryWhere(enabled: false),
        ),
        isFalse,
      );
    });

    test('filters by targetAppVersion null', () {
      final bundle = _testBundle(targetAppVersion: null);
      expect(
        bundleMatchesQueryWhere(
          bundle,
          const DatabaseBundleQueryWhere(targetAppVersionNotNull: true),
        ),
        isFalse,
      );
      expect(
        bundleMatchesQueryWhere(
          bundle,
          const DatabaseBundleQueryWhere(targetAppVersionNotNull: false),
        ),
        isTrue,
      );
    });
  });

  group('sortBundles', () {
    test('sorts descending by default', () {
      final bundles = [
        _testBundle(id: 'c'),
        _testBundle(id: 'a'),
        _testBundle(id: 'b'),
      ];
      final sorted = sortBundles(bundles, null);
      expect(sorted.map((b) => b.id).toList(), ['c', 'b', 'a']);
    });

    test('sorts ascending', () {
      final bundles = [
        _testBundle(id: 'c'),
        _testBundle(id: 'a'),
        _testBundle(id: 'b'),
      ];
      final sorted = sortBundles(
        bundles,
        const DatabaseBundleQueryOrder(direction: 'asc'),
      );
      expect(sorted.map((b) => b.id).toList(), ['a', 'b', 'c']);
    });
  });
}

Bundle _testBundle({
  String id = 'test-bundle-id',
  String channel = 'production',
  bool enabled = true,
  String? targetAppVersion = '1.0.0',
}) {
  return Bundle(
    id: id,
    channel: channel,
    platform: Platform.android,
    enabled: enabled,
    shouldForceUpdate: false,
    fileHash: 'abc123',
    gitCommitHash: null,
    message: null,
    targetAppVersion: targetAppVersion,
    fingerprintHash: null,
    storageUri: 'supabase-storage://bucket/path',
    metadata: const BundleMetadata(),
    patches: const [],
    rolloutCohortCount: 1000,
    targetCohorts: null,
  );
}
