import 'package:flutter_ota_kit_plugin_core/src/bundle_unit_of_work.dart';
import 'package:flutter_ota_kit_plugin_core/src/types.dart';
import 'package:test/test.dart';

Bundle _bundle(String id, {
  String channel = 'production',
  Platform platform = Platform.android,
  bool enabled = true,
  String? targetAppVersion,
  String? fingerprintHash,
}) => Bundle(
  id: id,
  platform: platform,
  shouldForceUpdate: false,
  enabled: enabled,
  fileHash: 'hash_$id',
  storageUri: 's3://bucket/$id.zip',
  channel: channel,
  targetAppVersion: targetAppVersion,
  fingerprintHash: fingerprintHash,
);

void main() {
  group('BundleUnitOfWork', () {
    late BundleUnitOfWork uow;

    setUp(() {
      uow = BundleUnitOfWork();
    });

    group('seed', () {
      test('adds bundles to entries', () {
        uow.seed([_bundle('a'), _bundle('b')]);
        expect(uow.peek('a'), isNotNull);
        expect(uow.peek('b'), isNotNull);
      });

      test('ignores null entries', () {
        uow.seed([_bundle('a'), null]);
        expect(uow.peek('a'), isNotNull);
      });

      test('hasSeeds reports correctly', () {
        expect(uow.hasSeeds(), isFalse);
        uow.seed([_bundle('a')]);
        expect(uow.hasSeeds(), isTrue);
      });

      test('seededBundles returns present bundles', () {
        uow.seed([_bundle('a'), _bundle('b')]);
        final seeded = uow.seededBundles();
        expect(seeded.length, 2);
        expect(seeded.map((b) => b.id).toSet(), {'a', 'b'});
      });

      test('seed does not override tracked changes', () {
        final b1 = _bundle('a');
        uow.markInsert(b1);
        // Seed with different data — insert should stay
        uow.seed([Bundle(
          id: 'a', platform: Platform.android, shouldForceUpdate: false,
          enabled: false, fileHash: 'other', storageUri: 'other',
          channel: 'production',
        )]);
        final changed = uow.changedSets();
        expect(changed.length, 1);
        expect(changed.first.data.fileHash, 'hash_a'); // original insert
      });
    });

    group('peek', () {
      test('returns null for missing', () {
        expect(uow.peek('missing'), isNull);
      });

      test('returns inserted bundle', () {
        final b = _bundle('x');
        uow.markInsert(b);
        expect(uow.peek('x'), equals(b));
      });

      test('returns null after delete', () {
        final b = _bundle('x');
        uow.markInsert(b);
        uow.markDelete(b);
        expect(uow.peek('x'), isNull);
      });
    });

    group('peekChanged', () {
      test('returns not found for unchanged', () {
        expect(uow.peekChanged('x'), isA<TrackedBundleNotFound>());
      });

      test('returns found for insert', () {
        final b = _bundle('x');
        uow.markInsert(b);
        final result = uow.peekChanged('x');
        expect(result, isA<TrackedBundleFound>());
        expect((result as TrackedBundleFound).value, equals(b));
      });

      test('returns found with null value for delete', () {
        final b = _bundle('x');
        uow.markInsert(b);
        uow.markDelete(b);
        final result = uow.peekChanged('x');
        expect(result, isA<TrackedBundleFound>());
        expect((result as TrackedBundleFound).value, isNull);
      });
    });

    group('getById (deduped async load)', () {
      test('returns cached entry on second call', () {
        var loadCount = 0;
        uow.seed([_bundle('a')]);
        return uow.getById('a', () async {
          loadCount++;
          return _bundle('a');
        }).then((b) {
          expect(b, isNotNull);
          expect(loadCount, 0); // never called — seed provided it
        });
      });

      test('loads and caches missing entry', () async {
        final b = _bundle('x');
        final result = await uow.getById('x', () async => b);
        expect(result, equals(b));
        expect(uow.peek('x'), equals(b)); // cached
      });

      test('caches null result as missing', () async {
        final result = await uow.getById('missing', () async => null);
        expect(result, isNull);
        // Second call should not invoke loader
        var called = false;
        final result2 = await uow.getById('missing', () async {
          called = true;
          return null;
        });
        expect(result2, isNull);
        expect(called, isFalse);
      });

      test('coalesces concurrent loads', () async {
        var loadCount = 0;
        final results = await Future.wait([
          uow.getById('x', () async {
            loadCount++;
            return _bundle('x');
          }),
          uow.getById('x', () async {
            loadCount++;
            return _bundle('x');
          }),
        ]);
        expect(results[0], isNotNull);
        expect(results[1], isNotNull);
        expect(loadCount, 1);
      });
    });

    group('markInsert / markUpdate / markDelete', () {
      test('markInsert tracks as insert', () {
        uow.markInsert(_bundle('a'));
        final sets = uow.changedSets();
        expect(sets.length, 1);
        expect(sets.first.operation, BundleChangeOperation.insert);
      });

      test('markUpdate on existing insert keeps insert', () {
        final b1 = _bundle('a');
        final b2 = Bundle(
          id: 'a', platform: Platform.android, shouldForceUpdate: false,
          enabled: false, fileHash: 'hash2', storageUri: 'uri2',
          channel: 'production',
        );
        uow.markInsert(b1);
        uow.markUpdate(b2);
        final sets = uow.changedSets();
        expect(sets.length, 1);
        expect(sets.first.operation, BundleChangeOperation.insert);
        expect(sets.first.data.fileHash, 'hash2');
      });

      test('markUpdate on seeded bundle tracks as update with before', () {
        uow.seed([_bundle('a')]);
        uow.markUpdate(_bundle('a'));
        final sets = uow.changedSets();
        expect(sets.length, 1);
        expect(sets.first.operation, BundleChangeOperation.update);
      });

      test('markDelete tracks as delete', () {
        uow.seed([_bundle('a')]);
        uow.markDelete(_bundle('a'));
        final sets = uow.changedSets();
        expect(sets.length, 1);
        expect(sets.first.operation, BundleChangeOperation.delete);
      });
    });

    group('hasChanges / listFetchExtraCount', () {
      test('hasChanges is false initially', () {
        expect(uow.hasChanges(), isFalse);
      });

      test('hasChanges is true after markInsert', () {
        uow.markInsert(_bundle('a'));
        expect(uow.hasChanges(), isTrue);
      });

      test('listFetchExtraCount counts updates and deletes', () {
        uow.seed([_bundle('a'), _bundle('b'), _bundle('c')]);
        uow.markUpdate(_bundle('a'));
        uow.markDelete(_bundle('b'));
        expect(uow.listFetchExtraCount(), 2); // 1 update + 1 delete
      });

      test('listFetchExtraCount ignores inserts', () {
        uow.markInsert(_bundle('a'));
        expect(uow.listFetchExtraCount(), 0);
      });
    });

    group('totalDelta', () {
      test('returns 0 for no changes', () {
        expect(uow.totalDelta(null), 0);
      });

      test('returns -1 for delete matching where', () {
        uow.seed([_bundle('a', channel: 'beta')]);
        uow.markDelete(_bundle('a'));
        final delta = uow.totalDelta(
          const DatabaseBundleQueryWhere(channel: 'beta'),
        );
        expect(delta, -1);
      });

      test('returns +1 for update that newly matches where', () {
        uow.seed([_bundle('a', channel: 'production')]);
        uow.markUpdate(_bundle('a', channel: 'beta'));
        final delta = uow.totalDelta(
          const DatabaseBundleQueryWhere(channel: 'beta'),
        );
        expect(delta, 1);
      });

      test('returns 0 when update stays in same where', () {
        uow.seed([_bundle('a', channel: 'beta')]);
        uow.markUpdate(_bundle('a', channel: 'beta'));
        final delta = uow.totalDelta(
          const DatabaseBundleQueryWhere(channel: 'beta'),
        );
        expect(delta, 0);
      });
    });

    group('overlayList', () {
      test('applies in-memory updates over DB results', () {
        uow.seed([_bundle('db1'), _bundle('db2')]);
        uow.markUpdate(_bundle('db1'));

        final dbResults = [_bundle('db1'), _bundle('db2')];
        final result = uow.overlayList(
          dbResults,
          limit: 20,
          where: null,
          orderBy: null,
        );
        final ids = result.map((b) => b.id).toList();
        expect(ids, containsAll(['db1', 'db2']));
      });

      test('excludes inserts from overlay (visible only after commit)', () {
        uow.seed([_bundle('db1')]);
        uow.markInsert(_bundle('mem1'));

        final dbResults = [_bundle('db1')];
        final result = uow.overlayList(
          dbResults,
          limit: 20,
          where: null,
          orderBy: null,
        );
        final ids = result.map((b) => b.id).toList();
        expect(ids, contains('db1'));
        expect(ids, isNot(contains('mem1')));
      });

      test('respects limit', () {
        for (var i = 0; i < 10; i++) {
          uow.seed([_bundle('b$i')]);
        }
        final dbResults = List.generate(10, (i) => _bundle('b$i'));
        final result = uow.overlayList(
          dbResults,
          limit: 3,
          where: null,
          orderBy: null,
        );
        expect(result.length, 3);
      });

      test('deletes are excluded', () {
        uow.seed([_bundle('a'), _bundle('b')]);
        uow.markDelete(_bundle('a'));
        final dbResults = [_bundle('a'), _bundle('b')];
        final result = uow.overlayList(
          dbResults,
          limit: 20,
          where: null,
          orderBy: null,
        );
        expect(result.map((b) => b.id).toList(), ['b']);
      });
    });

    group('clear', () {
      test('resets all state', () {
        uow.seed([_bundle('a')]);
        uow.markInsert(_bundle('b'));
        uow.clear();
        expect(uow.hasChanges(), isFalse);
        expect(uow.hasSeeds(), isFalse);
        expect(uow.peek('a'), isNull);
        expect(uow.peek('b'), isNull);
      });
    });
  });
}
