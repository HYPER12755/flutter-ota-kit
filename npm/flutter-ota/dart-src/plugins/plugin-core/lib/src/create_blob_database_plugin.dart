import 'dart:convert';

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';

import 'bundle_unit_of_work.dart';
import 'create_database_plugin.dart';
import 'filter_compatible_app_versions.dart';
import 'paginate_bundles.dart';
import 'query_bundles.dart';
import 'resolve_update_info_from_bundles.dart';
import 'types.dart';

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

class _BundleWithKey {
  _BundleWithKey(this.bundle, {required this.updateJsonKey});

  final Bundle bundle;
  final String updateJsonKey;
}

class _TargetVersionMutation {
  _TargetVersionMutation({
    required this.channel,
    required this.platform,
  });

  final String channel;
  final String platform;
  final Set<String> additions = <String>{};
  final Set<String> removals = <String>{};
}

// ---------------------------------------------------------------------------
// Concurrency helpers
// ---------------------------------------------------------------------------

const int _storageOperationConcurrency = 8;

Future<List<TResult>> _mapWithConcurrency<T, TResult>(
  List<T> items,
  int concurrency,
  Future<TResult> Function(T item, int index) mapper,
) async {
  final results = List<TResult?>.filled(items.length, null);
  var nextIndex = 0;
  final workerCount = concurrency < items.length ? concurrency : items.length;

  await Future.wait(
    List.generate(workerCount, (_) async {
      while (true) {
        final index = nextIndex;
        nextIndex += 1;
        if (index >= items.length) break;
        results[index] = await mapper(items[index], index);
      }
    }),
  );

  return results.cast<TResult>();
}

Future<void> _forEachWithConcurrency<T>(
  List<T> items,
  int concurrency,
  Future<void> Function(T item, int index) mapper,
) async {
  for (var i = 0; i < items.length; i += concurrency) {
    final batch = items.sublist(
      i,
      i + concurrency > items.length ? items.length : i + concurrency,
    );
    await Future.wait(
      List.generate(batch.length, (j) => mapper(batch[j], i + j)),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Bundle _removeBundleInternalKeys(Bundle bundle) {
  return Bundle(
    id: bundle.id,
    platform: bundle.platform,
    shouldForceUpdate: bundle.shouldForceUpdate,
    enabled: bundle.enabled,
    fileHash: bundle.fileHash,
    storageUri: bundle.storageUri,
    channel: bundle.channel,
    gitCommitHash: bundle.gitCommitHash,
    message: bundle.message,
    targetAppVersion: bundle.targetAppVersion,
    fingerprintHash: bundle.fingerprintHash,
    metadata: bundle.metadata,
    manifestStorageUri: bundle.manifestStorageUri,
    manifestFileHash: bundle.manifestFileHash,
    assetBaseStorageUri: bundle.assetBaseStorageUri,
    patches: bundle.patches,
    patchBaseBundleId: bundle.patchBaseBundleId,
    patchBaseFileHash: bundle.patchBaseFileHash,
    patchFileHash: bundle.patchFileHashLegacy,
    patchStorageUri: bundle.patchStorageUri,
    rolloutCohortCount: bundle.rolloutCohortCount,
    targetCohorts: bundle.targetCohorts,
  );
}

String? normalizeTargetAppVersion(String? version) {
  if (version == null || version.isEmpty) return null;

  var normalized = version.replaceAll(RegExp(r'\s+'), ' ').trim();
  normalized = normalized.replaceAllMapped(
    RegExp(r'([><=~^]+)\s+(\d)'),
    (m) => '${m.group(1)}${m.group(2)}',
  );

  return normalized;
}

bool _isExactVersion(String? version) {
  if (version == null || version.isEmpty) return false;
  final normalized = normalizeTargetAppVersion(version);
  if (normalized == null) return false;
  return SemVer.tryParse(normalized) != null;
}

List<String> _getSemverNormalizedVersions(String version) {
  final normalized = normalizeTargetAppVersion(version) ?? version;
  final coerced = semverCoerce(normalized);
  if (coerced == null) return [normalized];

  final versions = <String>{};
  versions.add(coerced.toString());

  if (coerced.patch == 0) {
    versions.add('${coerced.major}.${coerced.minor}');
  }
  if (coerced.minor == 0 && coerced.patch == 0) {
    versions.add('${coerced.major}');
  }

  return versions.toList();
}

String _resolveStorageTarget({
  String? targetAppVersion,
  String? fingerprintHash,
}) {
  final target = normalizeTargetAppVersion(targetAppVersion) ?? fingerprintHash;
  if (target == null || target.isEmpty) {
    throw StateError('target not found');
  }
  return target;
}

List<String> _getManagementListPrefixes(DatabaseBundleQueryWhere? where) {
  if (where?.channel != null &&
      where?.platform != null &&
      where?.targetAppVersion is String) {
    final normalized =
        normalizeTargetAppVersion(where!.targetAppVersion as String);
    if (normalized != null) {
      return ['${where.channel}/${where.platform?.value}/$normalized/'];
    }
  }

  if (where?.channel != null && where?.platform != null) {
      return ['${where!.channel}/${where.platform?.value}/'];
  }

  if (where?.channel != null) {
    return ['${where!.channel}/'];
  }

  return [''];
}

String? _getChannelFromUpdateJsonKey(String key) {
  final match =
      RegExp(r'^([^/]+)/(?:ios|android)/[^/]+/update\.json$').firstMatch(key);
  return match?.group(1);
}

const _defaultDescOrder =
    DatabaseBundleQueryOrder(field: 'id', direction: 'desc');

List<Bundle> _sortManagedBundles(
  List<Bundle> bundles,
  DatabaseBundleQueryOrder? orderBy,
) {
  return sortBundles(bundles, orderBy ?? _defaultDescOrder);
}

Bundle _mergeBundleUpdate(Bundle base, Map<String, Object?> patch) {
  const replaceOnUpdateKeys = ['patches', 'targetCohorts'];
  final baseMap = base.toJson();
  for (final key in patch.keys) {
    final srcValue = patch[key];
    if (replaceOnUpdateKeys.contains(key)) {
      baseMap[key] = srcValue;
    } else if (srcValue != null) {
      baseMap[key] = srcValue;
    }
  }
  return Bundle.fromJson(baseMap);
}

// ---------------------------------------------------------------------------
// BlobOperations interface
// ---------------------------------------------------------------------------

abstract class BlobOperations {
  Future<List<String>> listObjects(String prefix);
  Future<T?> loadObject<T>(String key);
  Future<void> uploadObject<T>(String key, T data);
  Future<void> deleteObject(String key);
  bool shouldSkipLoadObjectError(Object error, String key);
  void validateChannel(String channel);
  Future<void> invalidatePaths(List<String> paths);
  String get apiBasePath;
}

// ---------------------------------------------------------------------------
// createBlobDatabasePlugin
// ---------------------------------------------------------------------------

DatabasePlugin Function() Function(TConfig, [DatabasePluginHooks? hooks])
    createBlobDatabasePlugin<TConfig>({
  required String name,
  required BlobOperations Function(TConfig config) blobFactory,
}) {
  return (TConfig config, [DatabasePluginHooks? hooks]) {
    final ops = blobFactory(config);

    final bundlesMap = <String, _BundleWithKey>{};
    final pendingBundlesMap = <String, _BundleWithKey>{};
    final locallyDeletedBundleIds = <String>{};

    final createPlugin = createDatabasePlugin<TConfig>(
      name: name,
      factory: (_) => _BlobDatabasePlugin(
        hooks: hooks,
        ops: ops,
        bundlesMap: bundlesMap,
        pendingBundlesMap: pendingBundlesMap,
        locallyDeletedBundleIds: locallyDeletedBundleIds,
      ),
    )(config, hooks);

    return () => createPlugin();
  };
}

// ---------------------------------------------------------------------------
// Plugin implementation
// ---------------------------------------------------------------------------

class _BlobDatabasePlugin implements AbstractDatabasePlugin {
  _BlobDatabasePlugin({
    required this.hooks,
    required this.ops,
    required this.bundlesMap,
    required this.pendingBundlesMap,
    required this.locallyDeletedBundleIds,
  });

  final DatabasePluginHooks? hooks;
  final BlobOperations ops;
  final Map<String, _BundleWithKey> bundlesMap;
  final Map<String, _BundleWithKey> pendingBundlesMap;
  final Set<String> locallyDeletedBundleIds;

  // -- Storage helpers --

  Future<T?> loadOptionalObject<T>(String key) async {
    try {
      return await ops.loadObject<T>(key);
    } catch (error) {
      if (ops.shouldSkipLoadObjectError(error, key)) return null;
      rethrow;
    }
  }

  List<Bundle> bundlesFromKey(String key, List<Bundle> bundles) {
    for (final bundle in bundles) {
      if (locallyDeletedBundleIds.contains(bundle.id) ||
          pendingBundlesMap.containsKey(bundle.id)) {
        continue;
      }
      bundlesMap[bundle.id] = _BundleWithKey(bundle, updateJsonKey: key);
    }
    return bundles;
  }

  Future<List<Bundle>> loadBundleObject(String key) async {
    final bundles = (await loadOptionalObject<List>(key))
            ?.map((e) => Bundle.fromJson((e as Map).cast<String, dynamic>()))
            .toList() ??
        <Bundle>[];
    bundlesFromKey(key, bundles);
    return bundles;
  }

  Future<List<_BundleWithKey>> reloadBundles([
    List<String> prefixes = const [''],
  ]) async {
    bundlesMap.clear();
    pendingBundlesMap.clear();
    locallyDeletedBundleIds.clear();

    final updateJsonKeys = (await _mapWithConcurrency(
      prefixes,
      _storageOperationConcurrency,
      (prefix, _) => ops.listObjects(prefix),
    ))
        .expand((keys) => keys)
        .where((key) =>
            RegExp(r'^[^/]+/(?:ios|android)/[^/]+/update\.json$')
                .hasMatch(key))
        .toList();

    final allBundles = (await _mapWithConcurrency(
      updateJsonKeys,
      _storageOperationConcurrency,
      (key, _) async {
        final bundlesData = await loadBundleObject(key);
        return bundlesData
            .map((b) => _BundleWithKey(b, updateJsonKey: key))
            .toList();
      },
    ))
        .expand((b) => b)
        .toList();

    for (final entry in allBundles) {
      bundlesMap[entry.bundle.id] = entry;
    }

    for (final entry in pendingBundlesMap.entries) {
      bundlesMap[entry.key] = entry.value;
    }

    final sorted = List<_BundleWithKey>.from(bundlesMap.values);
    sorted.sort((a, b) => b.bundle.id.compareTo(a.bundle.id));
    return sorted;
  }

  Future<List<Bundle>> loadAllBundlesForManagementFallback(
    DatabaseBundleQueryWhere? where,
  ) async {
    return _sortManagedBundles(
      (await reloadBundles(_getManagementListPrefixes(where)))
          .map((e) => _removeBundleInternalKeys(e.bundle))
          .toList(),
      null,
    );
  }

  // -- Target version mutations --

  _TargetVersionMutation _getTargetVersionMutation(
    Map<String, _TargetVersionMutation> mutations,
    Bundle bundle,
  ) {
    final key = '${bundle.channel}/${bundle.platform}';
    var existing = mutations[key];
    if (existing != null) return existing;
    existing = _TargetVersionMutation(
      channel: bundle.channel,
      platform: bundle.platform.value,
    );
    mutations[key] = existing;
    return existing;
  }

  void _addTargetVersionAddition(
    Map<String, _TargetVersionMutation> mutations,
    Bundle bundle,
  ) {
    final v = normalizeTargetAppVersion(bundle.targetAppVersion);
    if (v == null) return;
    _getTargetVersionMutation(mutations, bundle).additions.add(v);
  }

  void _addTargetVersionRemoval(
    Map<String, _TargetVersionMutation> mutations,
    Bundle bundle,
  ) {
    final v = normalizeTargetAppVersion(bundle.targetAppVersion);
    if (v == null) return;
    _getTargetVersionMutation(mutations, bundle).removals.add(v);
  }

  Future<void> applyTargetVersionMutations(
    Map<String, _TargetVersionMutation> mutations,
  ) async {
    await Future.wait(
      mutations.values.map((mutation) async {
        final targetKey =
            '${mutation.channel}/${mutation.platform}/target-app-versions.json';
        final oldTargetVersions =
            (await loadOptionalObject<List>(targetKey))
                    ?.map((e) => e.toString())
                    .toList() ??
                <String>[];
        final newTargetVersions = oldTargetVersions
            .where((v) =>
                !mutation.removals.contains(v) ||
                mutation.additions.contains(v))
            .toList();
        for (final version in mutation.additions) {
          if (!newTargetVersions.contains(version)) {
            newTargetVersions.add(version);
          }
        }
        if (jsonEncode(oldTargetVersions) != jsonEncode(newTargetVersions)) {
          await ops.uploadObject(targetKey, newTargetVersions);
        }
      }),
    );
  }

  // -- Invalidation paths --

  void _addAppVersionInvalidationPaths(
    Set<String> pathsToInvalidate, {
    required String platform,
    required String channel,
    required String targetAppVersion,
  }) {
    if (!_isExactVersion(targetAppVersion)) {
      pathsToInvalidate.add('${ops.apiBasePath}/app-version/$platform/*');
      return;
    }
    for (final v in _getSemverNormalizedVersions(targetAppVersion)) {
      pathsToInvalidate
          .add('${ops.apiBasePath}/app-version/$platform/$v/$channel/*');
    }
  }

  void _addLookupInvalidationPaths(
    Set<String> pathsToInvalidate, {
    required String platform,
    required String channel,
    String? targetAppVersion,
    String? fingerprintHash,
  }) {
    if (fingerprintHash != null && fingerprintHash.isNotEmpty) {
      pathsToInvalidate.add(
        '${ops.apiBasePath}/fingerprint/$platform/$fingerprintHash/$channel/*',
      );
      return;
    }
    if (targetAppVersion != null && targetAppVersion.isNotEmpty) {
      _addAppVersionInvalidationPaths(
        pathsToInvalidate,
        platform: platform,
        channel: channel,
        targetAppVersion: targetAppVersion,
      );
    }
  }

  // -- Update info resolvers --

  Future<UpdateInfo?> _getAppVersionUpdateInfo(
    AppVersionGetBundlesArgs args,
    Map<String, Object?>? context,
  ) async {
    final channel = args.channel;
    final platform = args.platform;

    final targetVersionsKey = '$channel/${platform.value}/target-app-versions.json';
    final targetAppVersions =
        (await loadOptionalObject<List>(targetVersionsKey))
                ?.map((e) => e.toString())
                .toList() ??
            <String>[];
    final matchingVersions =
        filterCompatibleAppVersions(targetAppVersions, args.appVersion);

    final bundles = (await _mapWithConcurrency(
      matchingVersions,
      _storageOperationConcurrency,
      (targetAppVersion, _) async {
        final nv =
            normalizeTargetAppVersion(targetAppVersion) ?? targetAppVersion;
        return loadBundleObject('$channel/${platform.value}/$nv/update.json');
      },
    ))
        .expand((b) => b)
        .toList();

    return resolveUpdateInfoFromBundles(
      ResolveUpdateInfoFromBundlesOptions(
        args: AppVersionGetBundlesArgs(
          appVersion: args.appVersion,
          bundleId: args.bundleId,
          channel: channel,
          cohort: args.cohort,
          minBundleId: args.minBundleId,
          platform: platform,
        ),
        bundles: bundles,
        context: context,
      ),
    );
  }

  Future<UpdateInfo?> _getFingerprintUpdateInfo(
    FingerprintGetBundlesArgs args,
    Map<String, Object?>? context,
  ) async {
    final channel = args.channel;
    final platform = args.platform;

    final bundles = await loadBundleObject(
      '$channel/${platform.value}/${args.fingerprintHash}/update.json',
    );

    return resolveUpdateInfoFromBundles(
      ResolveUpdateInfoFromBundlesOptions(
        args: FingerprintGetBundlesArgs(
          bundleId: args.bundleId,
          channel: channel,
          cohort: args.cohort,
          fingerprintHash: args.fingerprintHash,
          minBundleId: args.minBundleId,
          platform: platform,
        ),
        bundles: bundles,
        context: context,
      ),
    );
  }

  // -- DatabasePlugin interface --

  @override
  Future<Bundle?> getBundleById(String bundleId) async {
    if (locallyDeletedBundleIds.contains(bundleId)) return null;

    final pending = pendingBundlesMap[bundleId];
    if (pending != null) return _removeBundleInternalKeys(pending.bundle);

    final cached = bundlesMap[bundleId];
    if (cached != null) return _removeBundleInternalKeys(cached.bundle);

    final bundles = await reloadBundles();
    for (final entry in bundles) {
      if (entry.bundle.id == bundleId) {
        return _removeBundleInternalKeys(entry.bundle);
      }
    }
    return null;
  }

  @override
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args) async {
    if (args is AppVersionGetBundlesArgs) {
      return _getAppVersionUpdateInfo(args, null);
    }
    return _getFingerprintUpdateInfo(args as FingerprintGetBundlesArgs, null);
  }

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) async {
    var allBundles =
        await loadAllBundlesForManagementFallback(options.where);
    if (options.where != null) {
      allBundles = allBundles
          .where((b) => bundleMatchesQueryWhere(b, options.where))
          .toList();
    }
    return paginateBundles(
      bundles: allBundles,
      limit: options.limit,
      offset: options.offset ??
          (options.page != null ? (options.page! - 1) * options.limit : null),
      cursor: options.cursor,
      orderBy: options.orderBy,
    );
  }

  @override
  Future<List<String>> getChannels() async {
    final channels = (await ops.listObjects(''))
        .map(_getChannelFromUpdateJsonKey)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    return channels;
  }

  @override
  Future<void> commitBundle({
    required List<BundleChange> changedSets,
  }) async {
    if (changedSets.isEmpty) return;

    for (final change in changedSets) {
      if (change.operation == BundleChangeOperation.insert ||
          (change.operation == BundleChangeOperation.update &&
              change.data.channel.isNotEmpty)) {
        ops.validateChannel(change.data.channel);
      }
    }

    final changedBundlesByKey = <String, List<Bundle>>{};
    final removalsByKey = <String, List<String>>{};
    final targetVersionRemovalsByKey = <String, List<_BundleWithKey>>{};
    final pathsToInvalidate = <String>{};
    final targetVersionMutations = <String, _TargetVersionMutation>{};

    for (final change in changedSets) {
      final data = change.data;

      // Insert
      if (change.operation == BundleChangeOperation.insert) {
        final target = _resolveStorageTarget(
          targetAppVersion: data.targetAppVersion,
          fingerprintHash: data.fingerprintHash,
        );
        final key =
            '${data.channel}/${data.platform.value}/$target/update.json';
        final bundleWithKey = _BundleWithKey(data, updateJsonKey: key);

        locallyDeletedBundleIds.remove(data.id);
        bundlesMap[data.id] = bundleWithKey;
        pendingBundlesMap[data.id] = bundleWithKey;

        changedBundlesByKey
            .putIfAbsent(key, () => <Bundle>[])
            .add(_removeBundleInternalKeys(data));

        _addTargetVersionAddition(targetVersionMutations, data);
        _addLookupInvalidationPaths(
          pathsToInvalidate,
          platform: data.platform.value,
          channel: data.channel,
          targetAppVersion: data.targetAppVersion,
          fingerprintHash: data.fingerprintHash,
        );
        continue;
      }

      // Delete
      if (change.operation == BundleChangeOperation.delete) {
        _BundleWithKey? bk = pendingBundlesMap[data.id];
        bk ??= bundlesMap[data.id];
        if (bk == null) throw StateError('Bundle to delete not found');

        bundlesMap.remove(data.id);
        pendingBundlesMap.remove(data.id);
        locallyDeletedBundleIds.add(data.id);

        removalsByKey
            .putIfAbsent(bk.updateJsonKey, () => <String>[])
            .add(bk.bundle.id);
        targetVersionRemovalsByKey
            .putIfAbsent(bk.updateJsonKey, () => <_BundleWithKey>[])
            .add(bk);

        _addLookupInvalidationPaths(
          pathsToInvalidate,
          platform: bk.bundle.platform.value,
          channel: bk.bundle.channel,
          targetAppVersion: bk.bundle.targetAppVersion,
          fingerprintHash: bk.bundle.fingerprintHash,
        );
        continue;
      }

      // Update
      _BundleWithKey? bk = pendingBundlesMap[data.id];
      bk ??= bundlesMap[data.id];
      if (bk == null) throw StateError('targetBundleId not found');

      if (change.operation == BundleChangeOperation.update) {
        final merged = _mergeBundleUpdate(bk.bundle, data.toJson());
        final newKey =
            '${merged.channel}/${merged.platform.value}/${_resolveStorageTarget(
          targetAppVersion: merged.targetAppVersion,
          fingerprintHash: merged.fingerprintHash,
        )}/update.json';

        if (newKey != bk.updateJsonKey) {
          // Key changed — remove from old, add to new.
          removalsByKey
              .putIfAbsent(bk.updateJsonKey, () => <String>[])
              .add(bk.bundle.id);
          targetVersionRemovalsByKey
              .putIfAbsent(bk.updateJsonKey, () => <_BundleWithKey>[])
              .add(bk);

          final updated = _BundleWithKey(merged, updateJsonKey: newKey);
          bundlesMap[data.id] = updated;
          pendingBundlesMap[data.id] = updated;
          locallyDeletedBundleIds.remove(data.id);

          changedBundlesByKey
              .putIfAbsent(newKey, () => <Bundle>[])
              .add(_removeBundleInternalKeys(merged));

          final oldChannel = bk.bundle.channel;
          final nextChannel = merged.channel;
          if (oldChannel != nextChannel) {
            _addLookupInvalidationPaths(
              pathsToInvalidate,
              platform: bk.bundle.platform.value,
              channel: oldChannel,
              targetAppVersion: bk.bundle.targetAppVersion,
              fingerprintHash: bk.bundle.fingerprintHash,
            );
            if (bk.bundle.targetAppVersion != null &&
                bk.bundle.fingerprintHash == null) {
              _addLookupInvalidationPaths(
                pathsToInvalidate,
                platform: merged.platform.value,
                channel: nextChannel,
                targetAppVersion: bk.bundle.targetAppVersion,
                fingerprintHash: bk.bundle.fingerprintHash,
              );
            }
          }

          _addTargetVersionAddition(targetVersionMutations, merged);
          _addLookupInvalidationPaths(
            pathsToInvalidate,
            platform: merged.platform.value,
            channel: merged.channel,
            targetAppVersion: merged.targetAppVersion,
            fingerprintHash: merged.fingerprintHash,
          );
          if (bk.bundle.targetAppVersion != null &&
              bk.bundle.targetAppVersion != merged.targetAppVersion) {
            _addLookupInvalidationPaths(
              pathsToInvalidate,
              platform: bk.bundle.platform.value,
              channel: bk.bundle.channel,
              targetAppVersion: bk.bundle.targetAppVersion,
              fingerprintHash: bk.bundle.fingerprintHash,
            );
          }
          continue;
        }

        // No key change
        final currentKey = bk.updateJsonKey;
        final updated = _BundleWithKey(merged, updateJsonKey: currentKey);
        bundlesMap[data.id] = updated;
        pendingBundlesMap[data.id] = updated;
        locallyDeletedBundleIds.remove(data.id);

        changedBundlesByKey
            .putIfAbsent(currentKey, () => <Bundle>[])
            .add(_removeBundleInternalKeys(merged));

        _addLookupInvalidationPaths(
          pathsToInvalidate,
          platform: merged.platform.value,
          channel: merged.channel,
          targetAppVersion: merged.targetAppVersion,
          fingerprintHash: merged.fingerprintHash,
        );
        _addTargetVersionAddition(targetVersionMutations, merged);
        if (bk.bundle.targetAppVersion != null &&
            bk.bundle.targetAppVersion != merged.targetAppVersion) {
          _addLookupInvalidationPaths(
            pathsToInvalidate,
            platform: bk.bundle.platform.value,
            channel: bk.bundle.channel,
            targetAppVersion: bk.bundle.targetAppVersion,
            fingerprintHash: bk.bundle.fingerprintHash,
          );
        }
      }
    }

    // Remove bundles from their old keys.
    await _forEachWithConcurrency(
      removalsByKey.keys.toList(),
      _storageOperationConcurrency,
      (oldKey, _) async {
        final currentBundles =
            (await loadOptionalObject<List>(oldKey))
                    ?.map((e) =>
                        Bundle.fromJson((e as Map).cast<String, dynamic>()))
                    .toList() ??
                <Bundle>[];
        final removalIds = removalsByKey[oldKey]!;
        final updatedBundles =
            currentBundles.where((b) => !removalIds.contains(b.id)).toList();
        updatedBundles.sort((a, b) => b.id.compareTo(a.id));

        if (updatedBundles.isEmpty) {
          await ops.deleteObject(oldKey);
          for (final removed in targetVersionRemovalsByKey[oldKey] ?? []) {
            _addTargetVersionRemoval(targetVersionMutations, removed.bundle);
          }
        } else {
          await ops.uploadObject(oldKey, updatedBundles);
        }
      },
    );

    // Add or update bundles in their new keys.
    await _forEachWithConcurrency(
      changedBundlesByKey.keys.toList(),
      _storageOperationConcurrency,
      (key, _) async {
        final currentBundles =
            (await loadOptionalObject<List>(key))
                    ?.map((e) =>
                        Bundle.fromJson((e as Map).cast<String, dynamic>()))
                    .toList() ??
                <Bundle>[];
        for (final changedBundle in changedBundlesByKey[key]!) {
          final idx =
              currentBundles.indexWhere((b) => b.id == changedBundle.id);
          if (idx >= 0) {
            currentBundles[idx] = changedBundle;
          } else {
            currentBundles.add(changedBundle);
          }
        }
        currentBundles.sort((a, b) => b.id.compareTo(a.id));
        await ops.uploadObject(key, currentBundles);
      },
    );

    if (targetVersionMutations.isNotEmpty) {
      await applyTargetVersionMutations(targetVersionMutations);
    }

    await ops.invalidatePaths(pathsToInvalidate.toList());

    pendingBundlesMap.clear();
  }

  @override
  final bool supportsCursorPagination = true;

  @override
  Future<void> onUnmount() async {}
}
