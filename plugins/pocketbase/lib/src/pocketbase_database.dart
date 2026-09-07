/// PocketBase-backed [DatabasePlugin] implementation.
///
/// Implements full parity with the Cloudflare/Supabase backends including
/// proper `getUpdateInfo` with `UpdateStrategy` branching, `bundle_patches`
/// support, and comprehensive filter operators.
library;

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';

import 'pocketbase_bundle_mapper.dart';
import 'pocketbase_client.dart';
import 'pocketbase_config.dart';

/// Configuration for the PocketBase database plugin.
typedef PocketBaseDatabaseConfig = PocketBaseConfig;

/// PocketBase-backed [AbstractDatabasePlugin] implementation.
class _PocketBaseDatabase implements AbstractDatabasePlugin {
  _PocketBaseDatabase(this.config, this.client);

  final PocketBaseConfig config;
  final PocketBaseClient client;

  static _PocketBaseDatabase build(PocketBaseConfig config) {
    final client = config.clientFactory != null
        ? config.clientFactory!(
            config.url,
            config.adminEmail,
            config.adminPassword,
          )
        : PocketBaseClient(config.url);
    client.adminCredentials(config.adminEmail, config.adminPassword);
    return _PocketBaseDatabase(config, client);
  }

  @override
  bool get supportsCursorPagination => false;

  // ----- Bundle patches -----

  String get _patchesCollection => '${config.bundlesCollection}_patches';

  Future<Map<String, List<Map<String, dynamic>>>> _getPatchMap(
    List<String> bundleIds,
  ) async {
    final patchMap = <String, List<Map<String, dynamic>>>{};
    if (bundleIds.isEmpty) return patchMap;

    final filter = bundleIds
        .map((id) => 'bundle_id = "${_escape(id)}"')
        .join(' || ');
    try {
      final res = await client.listRecords<dynamic>(
        _patchesCollection,
        (j) => j,
        filter: filter.isEmpty ? null : filter,
        sort: 'order_index',
        perPage: 500,
      );
      for (final item in res.items) {
        final row = item as Map<String, dynamic>;
        final bundleId = row['bundle_id'] as String? ?? '';
        if (bundleId.isNotEmpty) {
          (patchMap[bundleId] ??= []).add(row);
        }
      }
    } catch (_) {
      // patches collection may not exist yet; treat as no patches.
    }
    return patchMap;
  }

  // ----- Channels -----

  @override
  Future<List<String>> getChannels() async {
    try {
      final res = await client.listRecords<dynamic>(
        config.channelsCollection,
        (j) => j,
        perPage: 200,
        sort: 'name',
      );
      return res.items
          .map((j) => (j as Map)['name'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      // Fallback: extract distinct channels from bundles.
      final res = await client.listRecords<PocketBaseBundleRow>(
        config.bundlesCollection,
        PocketBaseBundleRow.fromJson,
        perPage: 500,
        sort: '-created',
      );
      final channels = <String>{};
      for (final b in res.items) {
        if (b.channel.isNotEmpty) channels.add(b.channel);
      }
      return channels.toList()..sort();
    }
  }

  // ----- Single bundle -----

  @override
  Future<Bundle?> getBundleById(String bundleId) async {
    final row = await client.getRecord<PocketBaseBundleRow>(
      config.bundlesCollection,
      bundleId,
      PocketBaseBundleRow.fromJson,
    );
    if (row == null) return null;
    final patchMap = await _getPatchMap([bundleId]);
    return mapRowToBundle(row, patches: patchMap[bundleId]);
  }

  // ----- Update info -----

  @override
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args) async {
    final channel = args.channel;
    final minBundleId = args.minBundleId;
    final platform = args.platform.value;

    if (args.updateStrategy == UpdateStrategy.appVersion) {
      final appVersion = (args as AppVersionGetBundlesArgs).appVersion;

      // 1. Collect distinct target_app_versions from enabled bundles.
      final allRes = await client.listRecords<PocketBaseBundleRow>(
        config.bundlesCollection,
        PocketBaseBundleRow.fromJson,
        filter: _buildFilter(
          channel: channel,
          platformValue: platform,
          enabled: true,
          idGte: minBundleId,
          targetAppVersionNotNull: true,
        ),
        sort: '-created',
        perPage: 500,
      );
      final targetVersions = allRes.items
          .map((b) => b.targetAppVersion)
          .whereType<String>()
          .toSet()
          .toList();

      // 2. Filter to compatible versions.
      final compatible = filterCompatibleAppVersions(targetVersions, appVersion);

      if (compatible.isEmpty) {
        // No compatible bundles — check if we should rollback.
        if (args.bundleId == nilUuid ||
            (minBundleId.isNotEmpty &&
                args.bundleId.compareTo(minBundleId) <= 0)) {
          return null;
        }
        return const UpdateInfo(
          id: nilUuid,
          shouldForceUpdate: true,
          message: null,
          status: UpdateStatus.rollback,
          storageUri: null,
          fileHash: null,
        );
      }

      // 3. Query bundles with compatible target_app_version using ?= operator.
      final filter = _buildFilter(
        channel: channel,
        platformValue: platform,
        enabled: true,
        idGte: minBundleId,
        targetAppVersionIn: compatible,
      );
      final res = await client.listRecords<PocketBaseBundleRow>(
        config.bundlesCollection,
        PocketBaseBundleRow.fromJson,
        filter: filter.isEmpty ? null : filter,
        sort: '-created',
        perPage: 500,
      );
      final bundles = res.items.map(mapRowToBundle).toList();
      final patchMap = await _getPatchMap(bundles.map((b) => b.id).toList());
      final bundlesWithPatches = bundles
          .map((b) => mapRowToBundle(
                res.items.firstWhere((r) => r.id == b.id),
                patches: patchMap[b.id],
              ))
          .toList();

      return resolveUpdateInfoFromBundles(
        ResolveUpdateInfoFromBundlesOptions(
          args: args,
          bundles: bundlesWithPatches,
        ),
      );
    }

    // Fingerprint strategy.
    final fingerprintHash = args is FingerprintGetBundlesArgs
        ? args.fingerprintHash
        : null;

    final filter = _buildFilter(
      channel: channel,
      platformValue: platform,
      enabled: true,
      idGte: minBundleId,
      fingerprintHash: fingerprintHash,
    );
    final res = await client.listRecords<PocketBaseBundleRow>(
      config.bundlesCollection,
      PocketBaseBundleRow.fromJson,
      filter: filter.isEmpty ? null : filter,
      sort: '-created',
      perPage: 500,
    );
    final bundles = res.items.map(mapRowToBundle).toList();
    final patchMap = await _getPatchMap(bundles.map((b) => b.id).toList());
    final bundlesWithPatches = bundles
        .map((b) => mapRowToBundle(
              res.items.firstWhere((r) => r.id == b.id),
              patches: patchMap[b.id],
            ))
        .toList();

    return resolveUpdateInfoFromBundles(
      ResolveUpdateInfoFromBundlesOptions(
        args: args,
        bundles: bundlesWithPatches,
      ),
    );
  }

  // ----- Query bundles -----

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) async {
    final where = options.where;
    final filter = _buildFilter(
      channel: where?.channel,
      platformValue: where?.platform?.value,
      enabled: where?.enabled,
      idEq: where?.id?.eq,
      idGt: where?.id?.gt,
      idLt: where?.id?.lt,
      targetAppVersion: where?.targetAppVersion,
      targetAppVersionIn: where?.targetAppVersionIn,
      targetAppVersionNotNull: where?.targetAppVersionNotNull,
      fingerprintHash: where?.fingerprintHash,
    );
    final orderField = options.orderBy?.field ?? 'id';
    final desc = options.orderBy?.direction != 'asc';
    final sort = (desc ? '-' : '') + orderField;
    final limit = options.limit == 0 ? 50 : options.limit;
    final page = (options.offset ?? 0) ~/ limit + 1;
    final list = await client.listRecords<PocketBaseBundleRow>(
      config.bundlesCollection,
      PocketBaseBundleRow.fromJson,
      filter: filter.isEmpty ? null : filter,
      sort: sort,
      page: page,
      perPage: limit,
    );
    final patchMap = await _getPatchMap(list.items.map((b) => b.id).toList());
    final total = list.totalItems;
    final totalPages = list.totalPages == 0 ? 1 : list.totalPages;
    final currentPage = list.page;
    final hasNextPage = currentPage < totalPages;
    final hasPreviousPage = currentPage > 1;
    return Paginated(
      data: list.items
          .map((row) => mapRowToBundle(row, patches: patchMap[row.id]))
          .toList(),
      pagination: PaginationInfo(
        total: total,
        hasNextPage: hasNextPage,
        hasPreviousPage: hasPreviousPage,
        currentPage: currentPage,
        totalPages: totalPages,
        nextCursor: list.items.isNotEmpty && hasNextPage
            ? list.items.last.id
            : null,
        previousCursor: list.items.isNotEmpty && hasPreviousPage
            ? list.items.first.id
            : null,
      ),
    );
  }

  // ----- Mutations (UnitOfWork) -----

  @override
  Future<void> commitBundle({required List<BundleChange> changedSets}) async {
    for (final change in changedSets) {
      switch (change.operation) {
        case BundleChangeOperation.insert:
          final row = _rowFromBundle(change.data);
          final exists = await client.recordExists(
            config.bundlesCollection,
            change.data.id,
          );
          if (exists) {
            await client.updateRecord<dynamic>(
              config.bundlesCollection,
              change.data.id,
              row.toCreateJson(),
              (j) => j,
            );
          } else {
            await client.createRecord<dynamic>(
              config.bundlesCollection,
              row.toCreateJson(),
              (j) => j,
            );
          }
          // Upsert patches.
          await _commitPatches(change.data);

        case BundleChangeOperation.update:
          final patch = _buildUpdatePatch(change.data);
          if (patch.isNotEmpty) {
            await client.updateRecord<dynamic>(
              config.bundlesCollection,
              change.data.id,
              patch,
              (j) => j,
            );
          }
          await _commitPatches(change.data);

        case BundleChangeOperation.delete:
          // Delete associated patches first.
          await _deletePatches(change.data.id);
          await client.deleteRecord(config.bundlesCollection, change.data.id);
      }
    }
  }

  Future<void> _commitPatches(Bundle bundle) async {
    final patches = bundle.patches;
    if (patches == null || patches.isEmpty) return;
    // Delete existing patches for this bundle, then re-create.
    await _deletePatches(bundle.id);
    for (var i = 0; i < patches.length; i++) {
      final p = patches[i];
      await client.createRecord<dynamic>(_patchesCollection, {
        'bundle_id': bundle.id,
        'base_bundle_id': p.baseBundleId,
        'base_file_hash': p.baseFileHash,
        'patch_file_hash': p.patchFileHash,
        'patch_storage_uri': p.patchStorageUri,
        'order_index': i,
      }, (j) => j);
    }
  }

  Future<void> _deletePatches(String bundleId) async {
    try {
      final res = await client.listRecords<dynamic>(
        _patchesCollection,
        (j) => j,
        filter: 'bundle_id = "${_escape(bundleId)}"',
        perPage: 500,
      );
      for (final item in res.items) {
        final id = (item as Map)['id'] as String?;
        if (id != null) {
          await client.deleteRecord(_patchesCollection, id);
        }
      }
    } catch (_) {
      // patches collection may not exist; ignore.
    }
  }

  @override
  Future<void> onUnmount() async {
    client.close();
  }

  // ----- Helpers -----

  PocketBaseBundleRow _rowFromBundle(Bundle v) => PocketBaseBundleRow(
    id: v.id,
    channel: v.channel,
    enabled: v.enabled,
    platform: v.platform.value,
    shouldForceUpdate: v.shouldForceUpdate,
    fileHash: v.fileHash,
    storageUri: v.storageUri,
    rolloutCohortCount: v.rolloutCohortCount ?? 1000,
    gitCommitHash: v.gitCommitHash,
    message: v.message,
    fingerprintHash: v.fingerprintHash,
    targetAppVersion: v.targetAppVersion,
    manifestStorageUri: v.manifestStorageUri,
    manifestFileHash: v.manifestFileHash,
    assetBaseStorageUri: v.assetBaseStorageUri,
    targetCohorts: v.targetCohorts,
    metadata: v.metadata?.toJson(),
  );

  String _buildFilter({
    String? channel,
    String? platformValue,
    Platform? platform,
    bool? enabled,
    String? idEq,
    String? idGt,
    String? idGte,
    String? idLt,
    String? idLte,
    List<String>? idIns,
    String? targetAppVersion,
    List<String>? targetAppVersionIn,
    bool? targetAppVersionNotNull,
    String? fingerprintHash,
  }) {
    final clauses = <String>[];
    if (channel != null && channel.isNotEmpty) {
      clauses.add('channel = "${_escape(channel)}"');
    }
    final pv = platformValue ?? platform?.value;
    if (pv != null) {
      clauses.add('platform = "${_escape(pv)}"');
    }
    if (enabled != null) {
      clauses.add('enabled = ${enabled ? 'true' : 'false'}');
    }
    if (idEq != null) clauses.add('id = "${_escape(idEq)}"');
    if (idGt != null) clauses.add('id > "${_escape(idGt)}"');
    if (idGte != null) clauses.add('id >= "${_escape(idGte)}"');
    if (idLt != null) clauses.add('id < "${_escape(idLt)}"');
    if (idLte != null) clauses.add('id <= "${_escape(idLte)}"');
    if (idIns != null && idIns.isNotEmpty) {
      final escaped = idIns.map((id) => '"${_escape(id)}"').join(',');
      clauses.add('id ?= [$escaped]');
    }
    if (targetAppVersion != null) {
      clauses.add('target_app_version = "${_escape(targetAppVersion)}"');
    }
    if (targetAppVersionIn != null && targetAppVersionIn.isNotEmpty) {
      final escaped =
          targetAppVersionIn.map((v) => '"${_escape(v)}"').join(',');
      clauses.add('target_app_version ?= [$escaped]');
    }
    if (targetAppVersionNotNull == true) {
      clauses.add('target_app_version != ""');
    }
    if (fingerprintHash != null) {
      clauses.add('fingerprint_hash = "${_escape(fingerprintHash)}"');
    }
    return clauses.join(' && ');
  }

  String _escape(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  Map<String, dynamic> _buildUpdatePatch(Bundle v) => {
    if (v.channel.isNotEmpty) 'channel': v.channel,
    'enabled': v.enabled,
    'platform': v.platform.value,
    'should_force_update': v.shouldForceUpdate,
    'rollout_cohort_count': v.rolloutCohortCount ?? 1000,
    'file_hash': v.fileHash,
    'storage_uri': v.storageUri,
    if (v.gitCommitHash != null) 'git_commit_hash': v.gitCommitHash,
    if (v.message != null) 'message': v.message,
    if (v.fingerprintHash != null) 'fingerprint_hash': v.fingerprintHash,
    if (v.targetAppVersion != null) 'target_app_version': v.targetAppVersion,
    if (v.manifestStorageUri != null)
      'manifest_storage_uri': v.manifestStorageUri,
    if (v.manifestFileHash != null) 'manifest_file_hash': v.manifestFileHash,
    if (v.assetBaseStorageUri != null)
      'asset_base_storage_uri': v.assetBaseStorageUri,
    if (v.targetCohorts != null) 'target_cohorts': v.targetCohorts,
    if (v.metadata != null) 'metadata': v.metadata!.toJson(),
  };
}

/// Build a `pocketbaseDatabase` plugin factory.
final pocketbaseDatabase = createDatabasePlugin<PocketBaseConfig>(
  name: 'pocketbaseDatabase',
  factory: _PocketBaseDatabase.build,
);
