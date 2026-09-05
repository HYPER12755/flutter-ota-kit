import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
import 'package:flutter_ota_kit_plugin_core/src/bundle_unit_of_work.dart';
import 'package:flutter_ota_kit_plugin_core/src/bundle_unit_of_work_store.dart';
import 'package:flutter_ota_kit_plugin_core/src/create_database_plugin.dart';
import 'package:flutter_ota_kit_plugin_core/src/types.dart';
import 'package:test/test.dart';

class _MockDatabasePlugin extends AbstractDatabasePlugin {
  _MockDatabasePlugin({required this.id, required this.bundles});

  final String id;
  final List<Bundle> bundles;

  final List<BundleChange> committedChanges = [];

  String get name => 'mock-$id';

  @override
  Future<Bundle?> getBundleById(String bundleId) async {
    return bundles.where((b) => b.id == bundleId).firstOrNull;
  }

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) async {
    final where = options.where;
    var filtered = bundles;
    if (where?.channel != null) {
      filtered = filtered.where((b) => b.channel == where!.channel).toList();
    }
    return Paginated(
      data: filtered,
      pagination: PaginationInfo(
        total: filtered.length,
        hasNextPage: false,
        hasPreviousPage: false,
        currentPage: 1,
        totalPages: 1,
      ),
    );
  }

  @override
  Future<List<String>> getChannels() async => ['production'];

  @override
  Future<void> commitBundle({required List<BundleChange> changedSets}) async {
    committedChanges.addAll(changedSets);
  }

  @override
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args) async => null;

  @override
  Future<void> onUnmount() async {}
}

Bundle _bundle(String id, {String channel = 'production'}) => Bundle(
  id: id,
  platform: Platform.android,
  shouldForceUpdate: false,
  enabled: true,
  fileHash: 'hash_$id',
  storageUri: 's3://bucket/$id.zip',
  channel: channel,
  targetAppVersion: '1.0.0',
);

void main() {
  setUp(() {
    clearUnitOfWorkStore();
  });

  group('createDatabasePlugin', () {
    late _MockDatabasePlugin mockImpl;

    setUp(() {
      mockImpl = _MockDatabasePlugin(
        id: 'test',
        bundles: [_bundle('b1'), _bundle('b2')],
      );
    });

    test('returns a factory function', () {
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) =>
            _MockDatabasePlugin(id: config, bundles: [_bundle('b1')]),
      );
      final createDb = factory('test');
      expect(createDb, isA<Function>());
    });

    test('factory creates a DatabasePlugin', () {
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) =>
            _MockDatabasePlugin(id: config, bundles: [_bundle('b1')]),
      );
      final db = factory('test')();
      expect(db, isA<DatabasePlugin>());
      expect(db.name, 'testDb');
    });

    test('getBundleById delegates to underlying impl', () async {
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) => _MockDatabasePlugin(
          id: config,
          bundles: [_bundle('b1'), _bundle('b2')],
        ),
      );
      final db = factory('test')();
      final result = await db.getBundleById('b1');
      expect(result, isNotNull);
      expect(result!.id, 'b1');
    });

    test('getBundleById returns null for missing', () async {
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) =>
            _MockDatabasePlugin(id: config, bundles: [_bundle('b1')]),
      );
      final db = factory('test')();
      final result = await db.getBundleById('missing');
      expect(result, isNull);
    });

    test('getBundles returns paginated results', () async {
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) => _MockDatabasePlugin(
          id: config,
          bundles: [_bundle('b1'), _bundle('b2')],
        ),
      );
      final db = factory('test')();
      final result = await db.getBundles(const DatabaseBundleQueryOptions());
      expect(result.data.length, 2);
      expect(result.pagination.total, 2);
    });

    test('getChannels delegates correctly', () async {
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) =>
            _MockDatabasePlugin(id: config, bundles: [_bundle('b1')]),
      );
      final db = factory('test')();
      final channels = await db.getChannels();
      expect(channels, ['production']);
    });

    test('appendBundle + commitBundle sends insert', () async {
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) => mockImpl,
      );
      final db = factory('test')();

      await db.appendBundle(_bundle('new'));
      await db.commitBundle();

      expect(mockImpl.committedChanges.length, 1);
      expect(
        mockImpl.committedChanges.first.operation,
        BundleChangeOperation.insert,
      );
      expect(mockImpl.committedChanges.first.data.id, 'new');
    });

    test('updateBundle + commitBundle sends update', () async {
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) => mockImpl,
      );
      final db = factory('test')();

      await db.updateBundle('b1', {'enabled': false});
      await db.commitBundle();

      expect(mockImpl.committedChanges.length, 1);
      expect(
        mockImpl.committedChanges.first.operation,
        BundleChangeOperation.update,
      );
      expect(mockImpl.committedChanges.first.data.enabled, false);
    });

    test('deleteBundle + commitBundle sends delete', () async {
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) => mockImpl,
      );
      final db = factory('test')();

      await db.deleteBundle(_bundle('b1'));
      await db.commitBundle();

      expect(mockImpl.committedChanges.length, 1);
      expect(
        mockImpl.committedChanges.first.operation,
        BundleChangeOperation.delete,
      );
    });

    test('commitBundle with no changes sends empty', () async {
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) => mockImpl,
      );
      final db = factory('test')();

      await db.commitBundle();
      expect(mockImpl.committedChanges, isEmpty);
    });

    test('each factory call creates isolated UoW', () async {
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) => mockImpl,
      );
      final db1 = factory('test')();
      final db2 = factory('test')();

      await db1.appendBundle(_bundle('only1'));
      // db2 should not have db1's changes
      await db2.commitBundle();
      expect(mockImpl.committedChanges, isEmpty);
    });

    test('hook onDatabaseUpdated fires after commit', () async {
      var hookCalled = false;
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) => mockImpl,
      );
      final db = factory(
        'test',
        DatabasePluginHooks(
          onDatabaseUpdated: () async {
            hookCalled = true;
          },
        ),
      )();

      await db.appendBundle(_bundle('x'));
      await db.commitBundle();
      expect(hookCalled, isTrue);
    });

    test('getUpdateInfo delegates to underlying impl', () async {
      final factory = createDatabasePlugin<String>(
        name: 'testDb',
        factory: (config) => mockImpl,
      );
      final db = factory('test')();
      final result = await db.getUpdateInfo(
        FingerprintGetBundlesArgs(
          platform: Platform.android,
          bundleId: 'b1',
          fingerprintHash: 'abc',
        ),
      );
      expect(result, isNull);
    });
  });

  group('mergeBundleUpdate', () {
    test('replaces targetCohorts', () {
      final base = _bundle('a');
      final updated = mergeBundleUpdate(base, {
        'targetCohorts': ['cohort1'],
      });
      expect(updated.targetCohorts, ['cohort1']);
    });

    test('replaces patches', () {
      final base = _bundle('a');
      final updated = mergeBundleUpdate(base, {'patches': []});
      expect(updated.patches, isEmpty);
    });

    test('updates scalar fields', () {
      final base = _bundle('a');
      final updated = mergeBundleUpdate(base, {'enabled': false});
      expect(updated.enabled, false);
    });

    test('preserves existing fields not in patch', () {
      final base = _bundle('a');
      final updated = mergeBundleUpdate(base, {'enabled': false});
      expect(updated.fileHash, 'hash_a');
    });
  });
}
