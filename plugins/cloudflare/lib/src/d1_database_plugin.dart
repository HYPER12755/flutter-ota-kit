import 'dart:convert' show jsonEncode;

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show
        AppVersionGetBundlesArgs,
        Bundle,
        FingerprintGetBundlesArgs,
        GetBundlesArgs,
        UpdateInfo,
        UpdateStrategy;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show
        AbstractDatabasePlugin,
        BundleChange,
        BundleChangeOperation,
        DatabaseBundleIdFilter,
        DatabaseBundleQueryOptions,
        DatabaseBundleQueryOrder,
        DatabaseBundleQueryWhere,
        Paginated,
        calculatePagination,
        filterCompatibleAppVersions,
        resolveUpdateInfoFromBundles,
        ResolveUpdateInfoFromBundlesOptions;

import 'd1_bundle_mapper.dart'
    show bundleToPatchRows, defaultRolloutCohortCount, transformRowToBundle;
import 'd1_build_where.dart' show buildWhereClause;
import 'd1_client.dart' show D1ClientLike;

/// Shared D1 database plugin logic used by both [d1Database] (REST API client)
/// and [cloudflareWorkerDatabase] (in-process D1 binding).
///
/// Issues raw SQLite statements and resolves update information in-process via
/// [resolveUpdateInfoFromBundles] (no SQL stored procedures, unlike the
/// Supabase/Postgres backends).
class D1DatabasePlugin implements AbstractDatabasePlugin {
  D1DatabasePlugin(this._client);

  final D1ClientLike _client;

  Future<Map<String, List<Map<String, dynamic>>>> _getPatchMap(
    List<String> bundleIds,
  ) async {
    final patchMap = <String, List<Map<String, dynamic>>>{};
    if (bundleIds.isEmpty) return patchMap;

    final rows = await _client.query(
      'SELECT * FROM bundle_patches '
      'WHERE bundle_id IN (SELECT value FROM json_each(?)) '
      'ORDER BY order_index ASC, base_bundle_id ASC',
      [jsonEncode(bundleIds)],
    );

    for (final row in rows) {
      (patchMap[row['bundle_id'] as String] ??= []).add(row);
    }
    return patchMap;
  }

  Future<int> _getTotalCount(DatabaseBundleQueryWhere conditions) async {
    final where = buildWhereClause(conditions);
    final rows = await _client.query(
      'SELECT COUNT(*) as total FROM bundles${where.sql}',
      where.params,
    );
    return (rows.firstOrNull?['total'] as num?)?.toInt() ?? 0;
  }

  Future<List<Bundle>> _getPaginatedBundles(
    DatabaseBundleQueryWhere conditions,
    int limit,
    int offset,
    DatabaseBundleQueryOrder? orderBy,
  ) async {
    final where = buildWhereClause(conditions);
    final orderBySql = orderBy?.direction == 'asc'
        ? 'ORDER BY id ASC'
        : 'ORDER BY id DESC';

    final rows = await _client.query(
      'SELECT * FROM bundles ${where.sql} $orderBySql LIMIT ? OFFSET ?',
      [...where.params, limit, offset],
    );

    final patchMap = await _getPatchMap(
      rows.map((row) => row['id'] as String).toList(),
    );
    return rows
        .map(
          (row) => transformRowToBundle(row, patchMap[row['id']] ?? const []),
        )
        .toList();
  }

  Future<List<Bundle>> _queryBundlesForUpdateInfo(
    DatabaseBundleQueryWhere conditions,
  ) async {
    final where = buildWhereClause(conditions);
    final rows = await _client.query(
      'SELECT * FROM bundles${where.sql}',
      where.params,
    );
    final patchMap = await _getPatchMap(
      rows.map((row) => row['id'] as String).toList(),
    );
    return rows
        .map(
          (row) => transformRowToBundle(row, patchMap[row['id']] ?? const []),
        )
        .toList();
  }

  Future<List<String>> _getTargetAppVersionsForUpdateInfo({
    required String channel,
    required String platform,
    required String minBundleId,
  }) async {
    final rows = await _client.query(
      'SELECT target_app_version FROM bundles '
      'WHERE channel = ? AND platform = ? AND enabled = 1 '
      'AND id >= ? AND target_app_version IS NOT NULL '
      'GROUP BY target_app_version',
      [channel, platform, minBundleId],
    );
    return rows.map((row) => row['target_app_version'] as String).toList();
  }

  @override
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args) async {
    final channel = args.channel;
    final minBundleId = args.minBundleId;
    final platform = args.platform.value;

    if (args.updateStrategy == UpdateStrategy.appVersion) {
      final appVersion = (args as AppVersionGetBundlesArgs).appVersion;
      final targetAppVersions = await _getTargetAppVersionsForUpdateInfo(
        channel: channel,
        platform: platform,
        minBundleId: minBundleId,
      );
      final compatibleAppVersions = filterCompatibleAppVersions(
        targetAppVersions,
        appVersion,
      );
      final bundles = compatibleAppVersions.isNotEmpty
          ? await _queryBundlesForUpdateInfo(
              DatabaseBundleQueryWhere(
                enabled: true,
                platform: args.platform,
                channel: channel,
                id: DatabaseBundleIdFilter(gte: minBundleId),
                targetAppVersionIn: compatibleAppVersions,
              ),
            )
          : const <Bundle>[];

      return resolveUpdateInfoFromBundles(
        ResolveUpdateInfoFromBundlesOptions(args: args, bundles: bundles),
      );
    }

    final fingerprintHash = args is FingerprintGetBundlesArgs
        ? args.fingerprintHash
        : null;

    final bundles = await _queryBundlesForUpdateInfo(
      DatabaseBundleQueryWhere(
        enabled: true,
        platform: args.platform,
        channel: channel,
        id: DatabaseBundleIdFilter(gte: minBundleId),
        fingerprintHash: fingerprintHash,
      ),
    );

    return resolveUpdateInfoFromBundles(
      ResolveUpdateInfoFromBundlesOptions(args: args, bundles: bundles),
    );
  }

  @override
  Future<Bundle?> getBundleById(String bundleId) async {
    final rows = await _client.query(
      'SELECT * FROM bundles WHERE id = ? LIMIT 1',
      [bundleId],
    );
    if (rows.isEmpty) return null;

    final patchMap = await _getPatchMap([bundleId]);
    return transformRowToBundle(rows.first, patchMap[bundleId] ?? const []);
  }

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) async {
    final where = options.where ?? const DatabaseBundleQueryWhere();
    final limit = options.limit;
    final offset =
        options.offset ??
        (options.page != null ? (options.page! - 1) * limit : 0);

    final totalCount = await _getTotalCount(where);
    final bundles = await _getPaginatedBundles(
      where,
      limit,
      offset,
      options.orderBy,
    );

    final pagination = calculatePagination(
      totalCount,
      limit: limit,
      offset: offset,
    );

    return Paginated<List<Bundle>>(data: bundles, pagination: pagination);
  }

  @override
  Future<List<String>> getChannels() async {
    final rows = await _client.query(
      'SELECT channel FROM bundles GROUP BY channel',
    );
    return rows.map((row) => row['channel'] as String).toList();
  }

  @override
  bool get supportsCursorPagination => false;

  @override
  Future<void> onUnmount() async {}

  @override
  Future<void> commitBundle({required List<BundleChange> changedSets}) async {
    if (changedSets.isEmpty) return;

    for (final op in changedSets) {
      if (op.operation == BundleChangeOperation.delete) {
        await _client.query('DELETE FROM bundle_patches WHERE bundle_id = ?', [
          op.data.id,
        ]);
        await _client.query(
          'DELETE FROM bundle_patches WHERE base_bundle_id = ?',
          [op.data.id],
        );
        await _client.query('DELETE FROM bundles WHERE id = ?', [op.data.id]);
      } else {
        final bundle = op.data;
        await _client.query(
          'INSERT OR REPLACE INTO bundles ('
          'id, channel, enabled, should_force_update, file_hash, '
          'git_commit_hash, message, platform, target_app_version, '
          'storage_uri, fingerprint_hash, metadata, manifest_storage_uri, '
          'manifest_file_hash, asset_base_storage_uri, rollout_cohort_count, '
          'target_cohorts) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            bundle.id,
            bundle.channel,
            bundle.enabled ? 1 : 0,
            bundle.shouldForceUpdate ? 1 : 0,
            bundle.fileHash,
            bundle.gitCommitHash,
            bundle.message,
            bundle.platform.value,
            bundle.targetAppVersion,
            bundle.storageUri,
            bundle.fingerprintHash,
            jsonEncode(bundle.metadata?.toJson() ?? <String, dynamic>{}),
            bundle.manifestStorageUri,
            bundle.manifestFileHash,
            bundle.assetBaseStorageUri,
            bundle.rolloutCohortCount ?? defaultRolloutCohortCount,
            bundle.targetCohorts != null
                ? jsonEncode(bundle.targetCohorts)
                : null,
          ],
        );

        await _client.query('DELETE FROM bundle_patches WHERE bundle_id = ?', [
          bundle.id,
        ]);

        final patchRows = bundleToPatchRows(bundle);
        for (final patchRow in patchRows) {
          await _client.query(
            'INSERT OR REPLACE INTO bundle_patches ('
            'id, bundle_id, base_bundle_id, base_file_hash, '
            'patch_file_hash, patch_storage_uri, order_index) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              patchRow['id'],
              patchRow['bundle_id'],
              patchRow['base_bundle_id'],
              patchRow['base_file_hash'],
              patchRow['patch_file_hash'],
              patchRow['patch_storage_uri'],
              patchRow['order_index'],
            ],
          );
        }
      }
    }
  }
}
