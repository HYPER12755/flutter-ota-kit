import 'package:flutter_patcher_core/flutter_patcher_core.dart';
import 'package:flutter_patcher_plugin_core/src/bundle_unit_of_work_store.dart';
import 'package:flutter_patcher_plugin_core/src/request_update_bundle_state.dart';
import 'package:test/test.dart';

Bundle _bundle(String id) => Bundle(
  id: id,
  platform: Platform.android,
  shouldForceUpdate: false,
  enabled: true,
  fileHash: 'hash_$id',
  storageUri: 's3://bucket/$id.zip',
  channel: 'production',
);

void main() {
  setUp(() {
    clearUnitOfWorkStore();
  });

  group('seedRequestUpdateBundles', () {
    test('seeds bundles into context UoW', () {
      final context = <String, Object?>{};
      seedRequestUpdateBundles(context, [_bundle('a'), _bundle('b')]);
      final seeds = getRequestUpdateBundleSeeds(context);
      expect(seeds.length, 2);
      expect(seeds.map((b) => b.id).toSet(), {'a', 'b'});
    });

    test('ignores null context', () {
      seedRequestUpdateBundles(null, [_bundle('a')]);
      // Should not throw
    });

    test('ignores empty seeds', () {
      final context = <String, Object?>{};
      seedRequestUpdateBundles(context, [null]);
      final seeds = getRequestUpdateBundleSeeds(context);
      expect(seeds, isEmpty);
    });

    test('filters out null seeds', () {
      final context = <String, Object?>{};
      seedRequestUpdateBundles(context, [_bundle('a'), null, _bundle('b')]);
      final seeds = getRequestUpdateBundleSeeds(context);
      expect(seeds.length, 2);
    });
  });

  group('getRequestUpdateBundleSeeds', () {
    test('returns empty for null context', () {
      expect(getRequestUpdateBundleSeeds(null), isEmpty);
    });

    test('returns empty for unseeded context', () {
      expect(getRequestUpdateBundleSeeds(<String, Object?>{}), isEmpty);
    });
  });

  group('createRequestUpdateBundleResolver', () {
    test('creates resolver for valid context', () async {
      final context = <String, Object?>{};
      seedRequestUpdateBundles(context, [_bundle('x')]);
      final resolver = createRequestUpdateBundleResolver(context);

      expect(resolver.hasSeededBundles, isTrue);
      expect(resolver.peek('x'), isNotNull);
      expect(resolver.peek('missing'), isNull);
    });

    test('creates standalone resolver for null context', () async {
      final resolver = createRequestUpdateBundleResolver(null);
      expect(resolver.hasSeededBundles, isFalse);
      expect(resolver.peek('anything'), isNull);
    });

    test('getById delegates to underlying UoW', () async {
      final context = <String, Object?>{};
      final resolver = createRequestUpdateBundleResolver(context);

      final result = await resolver.getById('y', () async => _bundle('y'));
      expect(result, isNotNull);
      expect(result!.id, 'y');
    });
  });
}
