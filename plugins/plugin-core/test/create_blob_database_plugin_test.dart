import 'dart:convert';

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _defaultBundleFields = <String, Object?>{
  'fileHash': 'hash',
  'gitCommitHash': null,
  'message': null,
  'enabled': true,
  'shouldForceUpdate': false,
  'storageUri':
      'storage://my-app/00000000-0000-0000-0000-000000000000/bundle.zip',
  'fingerprintHash': null,
};

Bundle createBundle(
  String channel,
  String platform,
  String targetAppVersion,
  String id,
) {
  return Bundle.fromJson({
    ..._defaultBundleFields,
    'channel': channel,
    'platform': platform,
    'targetAppVersion': targetAppVersion,
    'id': id,
  });
}

// ---------------------------------------------------------------------------
// Fake blob store
// ---------------------------------------------------------------------------

class _FakeBlobStore {
  final Map<String, String> data = {};
  final List<String> listObjectCalls = [];
  final List<String> loadObjectCalls = [];
  final List<String> invalidationCalls = [];

  void clear() {
    data.clear();
    listObjectCalls.clear();
    loadObjectCalls.clear();
    invalidationCalls.clear();
  }

  Future<List<String>> listObjects(String prefix) async {
    listObjectCalls.add(prefix);
    return data.keys.where((k) => k.startsWith(prefix)).toList();
  }

  Future<T?> loadObject<T>(String key) async {
    loadObjectCalls.add(key);
    final raw = data[key];
    if (raw == null) return null;
    return jsonDecode(raw) as T;
  }

  Future<void> uploadObject<T>(String key, T value) async {
    data[key] = jsonEncode(value);
  }

  Future<void> deleteObject(String key) async {
    data.remove(key);
  }

  Future<void> invalidatePaths(List<String> paths) async {
    invalidationCalls.addAll(paths);
  }

  bool shouldSkipLoadObjectError(Object error, String key) => false;
  void validateChannel(String channel) {}
}

_BlobOps _createOps(_FakeBlobStore store) => _BlobOps(store);

class _BlobOps implements BlobOperations {
  _BlobOps(this._store);
  final _FakeBlobStore _store;

  @override
  Future<List<String>> listObjects(String prefix) => _store.listObjects(prefix);
  @override
  Future<T?> loadObject<T>(String key) => _store.loadObject<T>(key);
  @override
  Future<void> uploadObject<T>(String key, T data) =>
      _store.uploadObject<T>(key, data);
  @override
  Future<void> deleteObject(String key) => _store.deleteObject(key);
  @override
  bool shouldSkipLoadObjectError(Object error, String key) =>
      _store.shouldSkipLoadObjectError(error, key);
  @override
  void validateChannel(String channel) => _store.validateChannel(channel);
  @override
  Future<void> invalidatePaths(List<String> paths) =>
      _store.invalidatePaths(paths);
  @override
  String get apiBasePath => '/api/check-update';
}

void _seedUpdateManifests(_FakeBlobStore store, List<Bundle> bundles) {
  final bundlesByKey = <String, List<Bundle>>{};
  final targetVersionsByKey = <String, Set<String>>{};

  for (final bundle in bundles) {
    final target = bundle.targetAppVersion ?? bundle.fingerprintHash;
    if (target == null) continue;

    final key =
        '${bundle.channel}/${bundle.platform.value}/$target/update.json';
    bundlesByKey.putIfAbsent(key, () => <Bundle>[]).add(bundle);

    if (bundle.targetAppVersion != null) {
      final tvKey =
          '${bundle.channel}/${bundle.platform.value}/target-app-versions.json';
      targetVersionsByKey
          .putIfAbsent(tvKey, () => <String>{})
          .add(bundle.targetAppVersion!);
    }
  }

  for (final entry in bundlesByKey.entries) {
    final sorted = entry.value..sort((a, b) => b.id.compareTo(a.id));
    store.data[entry.key] = jsonEncode(sorted.map((b) => b.toJson()).toList());
  }

  for (final entry in targetVersionsByKey.entries) {
    store.data[entry.key] = jsonEncode(entry.value.toList());
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeBlobStore store;
  late DatabasePlugin plugin;

  DatabasePlugin createPlugin() {
    return createBlobDatabasePlugin(
      name: 'blobDatabase',
      blobFactory: (_) => _createOps(store),
    )(null as dynamic)();
  }

  setUp(() {
    store = _FakeBlobStore();
    plugin = createPlugin();
  });

  group('update checks', () {
    test('uses direct app-version manifests for update checks', () async {
      final latest = createBundle(
        'production',
        'ios',
        '*',
        '00000000-0000-0000-0000-000000000002',
      );
      final previous = createBundle(
        'production',
        'ios',
        '*',
        '00000000-0000-0000-0000-000000000001',
      );

      _seedUpdateManifests(store, [previous, latest]);

      final updateInfo = await plugin.getUpdateInfo(
        AppVersionGetBundlesArgs(
          appVersion: '1.0.0',
          bundleId: '00000000-0000-0000-0000-000000000000',
          platform: Platform.ios,
        ),
      );

      expect(updateInfo, isNotNull);
      expect(updateInfo!.id, equals(latest.id));
      expect(updateInfo.status, equals(UpdateStatus.update));

      expect(store.listObjectCalls, isEmpty);
      expect(store.loadObjectCalls, [
        'production/ios/target-app-versions.json',
        'production/ios/*/update.json',
      ]);
    });

    test('uses fingerprint manifests directly for update checks', () async {
      final fingerprintBundle = Bundle.fromJson({
        ..._defaultBundleFields,
        'channel': 'production',
        'platform': 'ios',
        'targetAppVersion': null,
        'fingerprintHash': 'fingerprint-1',
        'id': '00000000-0000-0000-0000-000000000010',
      });

      _seedUpdateManifests(store, [fingerprintBundle]);

      final updateInfo = await plugin.getUpdateInfo(
        FingerprintGetBundlesArgs(
          bundleId: '00000000-0000-0000-0000-000000000000',
          fingerprintHash: 'fingerprint-1',
          platform: Platform.ios,
        ),
      );

      expect(updateInfo, isNotNull);
      expect(updateInfo!.id, equals(fingerprintBundle.id));
      expect(updateInfo.status, equals(UpdateStatus.update));

      expect(store.listObjectCalls, isEmpty);
      expect(store.loadObjectCalls, [
        'production/ios/fingerprint-1/update.json',
      ]);
    });

    test('respects cohort eligibility', () async {
      final gatedBundle = Bundle.fromJson({
        ...createBundle(
          'production',
          'ios',
          '*',
          '00000000-0000-0000-0000-000000000021',
        ).toJson(),
        'targetCohorts': ['beta'],
      });
      final fallback = createBundle(
        'production',
        'ios',
        '*',
        '00000000-0000-0000-0000-000000000020',
      );
      final fallbackWithCohort = Bundle.fromJson({
        ...fallback.toJson(),
        'targetCohorts': ['stable'],
      });

      _seedUpdateManifests(store, [fallbackWithCohort, gatedBundle]);

      final updateInfo = await plugin.getUpdateInfo(
        AppVersionGetBundlesArgs(
          appVersion: '1.0.0',
          bundleId: '00000000-0000-0000-0000-000000000000',
          cohort: 'stable',
          platform: Platform.ios,
        ),
      );

      expect(updateInfo, isNotNull);
      expect(updateInfo!.id, equals(fallbackWithCohort.id));
      expect(updateInfo.status, equals(UpdateStatus.update));
    });

    test('returns null when no candidates and bundleId = nil', () async {
      final updateInfo = await plugin.getUpdateInfo(
        AppVersionGetBundlesArgs(
          appVersion: '1.0.0',
          bundleId: '00000000-0000-0000-0000-000000000040',
          minBundleId: '00000000-0000-0000-0000-000000000040',
          platform: Platform.ios,
        ),
      );
      expect(updateInfo, isNull);
    });
  });

  group('append and commit', () {
    test('appends a new bundle and commits to blob store', () async {
      final bundle = createBundle(
        'production',
        'ios',
        '1.0.0',
        '00000000-0000-0000-0000-000000000001',
      );

      await plugin.appendBundle(bundle);
      await plugin.commitBundle();

      final bundleKey = 'production/ios/1.0.0/update.json';
      expect(store.data.containsKey(bundleKey), isTrue);

      final stored = jsonDecode(store.data[bundleKey]!) as List;
      expect(stored.length, equals(1));

      final fetched = await plugin.getBundleById(
        '00000000-0000-0000-0000-000000000001',
      );
      expect(fetched, isNotNull);
      expect(fetched!.id, equals(bundle.id));
    });

    test('does not write to store until commitBundle', () async {
      final bundle = createBundle(
        'production',
        'ios',
        '1.0.0',
        '00000000-0000-0000-0000-000000000010',
      );

      expect(store.data, isEmpty);

      await plugin.appendBundle(bundle);
      expect(store.data, isEmpty);

      await plugin.commitBundle();
      expect(
        store.data.containsKey('production/ios/1.0.0/update.json'),
        isTrue,
      );
    });

    test('appends multiple bundles to correct keys', () async {
      final b1 = createBundle('production', 'ios', '1.0.0', 'multi-1');
      final b2 = createBundle('production', 'android', '2.0.0', 'multi-2');

      await plugin.appendBundle(b1);
      await plugin.appendBundle(b2);
      await plugin.commitBundle();

      expect(
        store.data.containsKey('production/ios/1.0.0/update.json'),
        isTrue,
      );
      expect(
        store.data.containsKey('production/android/2.0.0/update.json'),
        isTrue,
      );
    });
  });

  group('update and delete', () {
    test('updates an existing bundle', () async {
      final bundle = createBundle(
        'production',
        'android',
        '2.0.0',
        '00000000-0000-0000-0000-000000000002',
      );
      final bundleKey = 'production/android/2.0.0/update.json';
      store.data[bundleKey] = jsonEncode([bundle.toJson()]);

      await plugin.getBundles(const DatabaseBundleQueryOptions(limit: 20));
      await plugin.updateBundle('00000000-0000-0000-0000-000000000002', {
        'enabled': false,
      });
      await plugin.commitBundle();

      final updated = jsonDecode(store.data[bundleKey]!) as List;
      expect(updated.length, equals(1));
      expect(updated[0]['enabled'], isFalse);
    });

    test('throws when updating non-existent bundle', () async {
      expect(
        () => plugin.updateBundle('nonexistent', {'enabled': true}),
        throwsA(isA<StateError>()),
      );
    });

    test('deletes a bundle successfully', () async {
      final b1 = createBundle('production', 'ios', '1.1.1', 'bundleX');
      final b2 = createBundle('production', 'android', '1.1.1', 'bundleY');

      await plugin.appendBundle(b1);
      await plugin.appendBundle(b2);
      await plugin.commitBundle();

      expect(await plugin.getBundleById('bundleX'), isNotNull);

      await plugin.deleteBundle(b1);
      await plugin.commitBundle();

      expect(await plugin.getBundleById('bundleX'), isNull);
      expect(await plugin.getBundleById('bundleY'), isNotNull);
    });

    test('deletes entire update.json when no bundles remain', () async {
      final b1 = createBundle('production', 'ios', '1.1.1', 'bundleX');

      await plugin.appendBundle(b1);
      await plugin.commitBundle();

      final updateJsonKeys = store.data.keys
          .where((k) => k.contains('update.json'))
          .toList();
      expect(updateJsonKeys, isNotEmpty);

      await plugin.deleteBundle(b1);
      await plugin.commitBundle();

      expect(store.data.containsKey(updateJsonKeys.first), isFalse);
    });

    test('keeps update.json when other bundles remain', () async {
      final b1 = {
        ..._defaultBundleFields,
        'id': 'bundleA',
        'channel': 'production',
        'platform': 'ios',
        'targetAppVersion': '1.1.1',
      };
      final b2 = {
        ..._defaultBundleFields,
        'id': 'bundleB',
        'channel': 'production',
        'platform': 'ios',
        'targetAppVersion': '1.1.1',
      };

      final bundle1 = Bundle.fromJson(b1);
      final bundle2 = Bundle.fromJson(b2);

      await plugin.appendBundle(bundle1);
      await plugin.appendBundle(bundle2);
      await plugin.commitBundle();

      await plugin.deleteBundle(bundle1);
      await plugin.commitBundle();

      final remaining = await plugin.getBundleById('bundleB');
      expect(remaining, isNotNull);
    });
  });

  group('targetAppVersion move', () {
    test('moves bundle between version paths', () async {
      final keyOld = 'production/ios/1.x.x/update.json';
      final keyNew = 'production/ios/1.0.2/update.json';

      final oldBundles = [
        createBundle(
          'production',
          'ios',
          '1.x.x',
          '00000000-0000-0000-0000-000000000003',
        ),
        createBundle(
          'production',
          'ios',
          '1.x.x',
          '00000000-0000-0000-0000-000000000002',
        ),
        createBundle(
          'production',
          'ios',
          '1.x.x',
          '00000000-0000-0000-0000-000000000001',
        ),
      ];

      final newBundles = [
        createBundle(
          'production',
          'ios',
          '1.0.2',
          '00000000-0000-0000-0000-000000000005',
        ),
        createBundle(
          'production',
          'ios',
          '1.0.2',
          '00000000-0000-0000-0000-000000000004',
        ),
      ];

      store.data[keyOld] = jsonEncode(
        oldBundles.map((b) => b.toJson()).toList(),
      );
      store.data[keyNew] = jsonEncode(
        newBundles.map((b) => b.toJson()).toList(),
      );
      store.data['production/ios/target-app-versions.json'] = jsonEncode([
        '1.x.x',
        '1.0.2',
      ]);

      await plugin.getBundles(const DatabaseBundleQueryOptions(limit: 20));

      await plugin.updateBundle('00000000-0000-0000-0000-000000000003', {
        'targetAppVersion': '1.0.2',
      });
      await plugin.commitBundle();

      final newFileBundles = jsonDecode(store.data[keyNew]!) as List;
      expect(newFileBundles.length, equals(3));

      final oldFileBundles = jsonDecode(store.data[keyOld]!) as List;
      expect(oldFileBundles.length, equals(2));
    });
  });

  group('getChannels', () {
    test('returns sorted unique channels', () async {
      final p1 = createBundle('production', 'ios', '1.0.0', 'ch-prod');
      final p2 = createBundle('beta', 'ios', '1.0.0', 'ch-beta');

      await plugin.appendBundle(p1);
      await plugin.appendBundle(p2);
      await plugin.commitBundle();

      final channels = await plugin.getChannels();
      expect(channels, ['beta', 'production']);
    });
  });

  group('getBundles', () {
    test('returns empty for no data', () async {
      final result = await plugin.getBundles(
        const DatabaseBundleQueryOptions(limit: 20),
      );
      expect(result.data, isEmpty);
      expect(result.pagination.total, equals(0));
    });

    test('sorts bundles descending by id', () async {
      final bA = createBundle('production', 'ios', '1.0.0', 'A');
      final bB = createBundle('production', 'ios', '1.0.0', 'B');
      final bC = createBundle('production', 'ios', '2.0.0', 'C');

      store.data['production/ios/1.0.0/update.json'] = jsonEncode([
        bB.toJson(),
        bA.toJson(),
      ]);
      store.data['production/ios/2.0.0/update.json'] = jsonEncode([
        bC.toJson(),
      ]);

      final result = await plugin.getBundles(
        const DatabaseBundleQueryOptions(limit: 20),
      );
      expect(result.data.length, equals(3));
      expect(result.data[0].id, 'C');
      expect(result.data[1].id, 'B');
      expect(result.data[2].id, 'A');
    });

    test('filters by channel and platform', () async {
      final ios = createBundle('production', 'ios', '1.0.0', 'ios-1');
      final android = createBundle(
        'production',
        'android',
        '1.0.0',
        'android-1',
      );

      store.data['production/ios/1.0.0/update.json'] = jsonEncode([
        ios.toJson(),
      ]);
      store.data['production/android/1.0.0/update.json'] = jsonEncode([
        android.toJson(),
      ]);

      final result = await plugin.getBundles(
        DatabaseBundleQueryOptions(
          limit: 20,
          where: const DatabaseBundleQueryWhere(
            channel: 'production',
            platform: Platform.ios,
          ),
        ),
      );
      expect(result.data.length, equals(1));
      expect(result.data[0].id, 'ios-1');
    });
  });

  group('CloudFront invalidation', () {
    test('invalidates correct paths on new bundle', () async {
      final bundle = createBundle(
        'production',
        'ios',
        '1.0.0',
        'cloudfront-new-test',
      );

      await plugin.appendBundle(bundle);
      await plugin.commitBundle();

      expect(store.invalidationCalls, isNotEmpty);
      expect(
        store.invalidationCalls.any(
          (p) => p.contains('app-version') && p.contains('1.0.0'),
        ),
        isTrue,
      );
      expect(
        store.invalidationCalls.any((p) => p.contains('update.json')),
        isFalse,
      );
    });

    test('invalidates semver pattern path', () async {
      final bundle = createBundle(
        'production',
        'ios',
        '3.0.x',
        'cloudfront-semver',
      );

      store.invalidationCalls.clear();
      await plugin.appendBundle(bundle);
      await plugin.commitBundle();

      expect(
        store.invalidationCalls.any(
          (p) => p == '/api/check-update/app-version/ios/*',
        ),
        isTrue,
      );
    });

    test('no invalidation when commitBundle has no changes', () async {
      store.invalidationCalls.clear();
      await plugin.commitBundle();
      expect(store.invalidationCalls, isEmpty);
    });
  });

  group('targetAppVersion with spaces', () {
    test('normalizes space-containing targetAppVersion', () async {
      final bundle = createBundle(
        'production',
        'ios',
        '>= 10.7.0',
        'space-normalization-test',
      );

      await plugin.appendBundle(bundle);
      await plugin.commitBundle();

      expect(
        store.data.containsKey('production/ios/>=10.7.0/update.json'),
        isTrue,
      );
    });

    test('normalizes multiple spaces', () async {
      final bundle = createBundle(
        'production',
        'android',
        '>  1.0.0   <   2.0.0',
        'multi-space-test',
      );

      await plugin.appendBundle(bundle);
      await plugin.commitBundle();

      expect(
        store.data.containsKey('production/android/>1.0.0 <2.0.0/update.json'),
        isTrue,
      );
    });

    test('handles various semver range formats', () async {
      final cases = [
        ('> 1.0.0', '>1.0.0'),
        ('< 2.0.0', '<2.0.0'),
        ('>= 1.0.0', '>=1.0.0'),
        ('<= 2.0.0', '<=2.0.0'),
        ('~  1.0.0', '~1.0.0'),
        ('^  2.0.0', '^2.0.0'),
      ];

      for (var i = 0; i < cases.length; i++) {
        final (version, normalized) = cases[i];
        final bundle = createBundle('production', 'ios', version, 'format-$i');
        await plugin.appendBundle(bundle);
      }

      await plugin.commitBundle();

      for (final (_, normalized) in cases) {
        expect(
          store.data.containsKey('production/ios/$normalized/update.json'),
          isTrue,
          reason: 'Missing key for $normalized',
        );
      }
    });

    test('normalizes target-app-versions.json', () async {
      final bundle = createBundle(
        'production',
        'ios',
        '>= 10.7.0',
        'target-versions-test',
      );

      await plugin.appendBundle(bundle);
      await plugin.commitBundle();

      final versions = jsonDecode(
        store.data['production/ios/target-app-versions.json']!,
      ) as List;
      expect(versions, contains('>=10.7.0'));
    });
  });

  group('semver normalization', () {
    test('invalidates all paths for 1.0.0', () async {
      final bundle = createBundle(
        'production',
        'ios',
        '1.0.0',
        'semver-normalization-test',
      );

      store.invalidationCalls.clear();
      await plugin.appendBundle(bundle);
      await plugin.commitBundle();

      expect(
        store.invalidationCalls.any((p) => p.contains('app-version/ios/1.0.0')),
        isTrue,
      );
      expect(
        store.invalidationCalls.any((p) => p.contains('app-version/ios/1.0')),
        isTrue,
      );
      expect(
        store.invalidationCalls.any((p) => p.contains('app-version/ios/1/')),
        isTrue,
      );
    });

    test('only normalizes 2.x when patch=0', () async {
      final bundle = createBundle(
        'production',
        'android',
        '2.1.0',
        'semver-norm-test-2',
      );

      store.invalidationCalls.clear();
      await plugin.appendBundle(bundle);
      await plugin.commitBundle();

      expect(
        store.invalidationCalls.any(
          (p) => p.contains('app-version/android/2.1.0'),
        ),
        isTrue,
      );
      expect(
        store.invalidationCalls.any(
          (p) => p.contains('app-version/android/2.1'),
        ),
        isTrue,
      );
      expect(
        store.invalidationCalls.any(
          (p) => RegExp(r'app-version/android/2/').hasMatch(p),
        ),
        isFalse,
      );
    });

    test('no extra normalization for 1.2.3', () async {
      final bundle = createBundle(
        'production',
        'ios',
        '1.2.3',
        'no-normalization-test',
      );

      store.invalidationCalls.clear();
      await plugin.appendBundle(bundle);
      await plugin.commitBundle();

      expect(
        store.invalidationCalls.any(
          (p) => p == '/api/check-update/app-version/ios/1.2.3/production/*',
        ),
        isTrue,
      );
      expect(
        store.invalidationCalls.any(
          (p) => p == '/api/check-update/app-version/ios/1.2/production/*',
        ),
        isFalse,
      );
      expect(
        store.invalidationCalls.any(
          (p) => p == '/api/check-update/app-version/ios/1/production/*',
        ),
        isFalse,
      );
    });
  });

  group('issue #745 promotion scenario', () {
    test('updates target-app-versions when promoting channel', () async {
      final bundle = createBundle(
        'test',
        'android',
        '8.1.3',
        'issue-745-promote-bundle',
      );

      await plugin.appendBundle(bundle);
      await plugin.commitBundle();

      store.invalidationCalls.clear();

      await plugin.updateBundle('issue-745-promote-bundle', {
        'channel': 'prod',
      });
      await plugin.commitBundle();

      expect(
        store.invalidationCalls.any(
          (p) => p.contains('app-version/android/8.1.3/test'),
        ),
        isTrue,
      );
      expect(
        store.invalidationCalls.any(
          (p) => p.contains('app-version/android/8.1.3/prod'),
        ),
        isTrue,
      );

      final prodVersions = jsonDecode(
        store.data['prod/android/target-app-versions.json'] ?? '[]',
      ) as List;
      expect(prodVersions, contains('8.1.3'));

      final testVersions = jsonDecode(
        store.data['test/android/target-app-versions.json'] ?? '[]',
      ) as List;
      expect(testVersions, isNot(contains('8.1.3')));
    });
  });
}
