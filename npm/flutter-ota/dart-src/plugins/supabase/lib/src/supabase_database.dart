/// Faithful port of hot-updater `plugins/supabase/src/supabaseDatabase.ts`.
library;

import 'dart:convert';

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';

import 'supabase_bundle_mapper.dart';
import 'supabase_client_adapter.dart';
import 'supabase_client_http.dart';
import 'supabase_config.dart';
import 'types.dart';

/// Configuration for the Supabase database plugin.
typedef SupabaseDatabaseConfig = SupabaseServiceRoleConfig;

/// Row shape returned by the update-info RPCs.
class _SupabaseUpdateInfoRow {
  final String id;
  final bool shouldForceUpdate;
  final String? message;
  final String status;
  final String? storageUri;
  final String? fileHash;

  const _SupabaseUpdateInfoRow({
    required this.id,
    required this.shouldForceUpdate,
    required this.message,
    required this.status,
    required this.storageUri,
    required this.fileHash,
  });
}

/// Row shape returned by `get_target_app_version_list`.
class _SupabaseTargetAppVersionRow {
  final String? targetAppVersion;

  const _SupabaseTargetAppVersionRow(this.targetAppVersion);
}

/// Build a throwable error from an unknown Supabase error value.
Object createSupabaseError(Object error) {
  if (error is Error) return error;
  if (error is Exception) return error;

  if (error is Map) {
    final props = <String, Object?>{};
    error.forEach((key, value) {
      props[key.toString()] = value;
    });
    return StateError(jsonEncode(props));
  }
  return StateError(error.toString());
}

UpdateInfo mapUpdateInfoRow(_SupabaseUpdateInfoRow row) => UpdateInfo(
      id: row.id,
      shouldForceUpdate: row.shouldForceUpdate,
      message: row.message,
      status: row.status == 'ROLLBACK' ? UpdateStatus.rollback : UpdateStatus.update,
      storageUri: row.storageUri,
      fileHash: row.fileHash,
    );

/// Supabase-backed [DatabasePlugin] factory.
///
/// Mirrors `supabaseDatabase` from hot-updater: a `createDatabasePlugin`
/// wrapper whose inner factory builds a Supabase client and returns an
/// [AbstractDatabasePlugin] implementation.
DatabasePlugin Function() Function(
  SupabaseDatabaseConfig config, [
  DatabasePluginHooks? hooks,
]) supabaseDatabase = createDatabasePlugin<SupabaseDatabaseConfig>(
  name: 'supabaseDatabase',
  factory: (config) {
    final supabase = (config.clientFactory != null
        ? config.clientFactory!(config.supabaseUrl, config.resolveKey())
        : createSupabaseHttpClient(
            config.supabaseUrl,
            config.resolveKey(),
          ));

    Future<Map<String, List<SupabaseBundlePatchRow>>> fetchPatchMap(
      List<String> bundleIds,
    ) async {
      final patchMap = <String, List<SupabaseBundlePatchRow>>{};
      if (bundleIds.isEmpty) return patchMap;

      final res = await supabase
          .from('bundle_patches')
          .select('*')
          .in_('bundle_id', bundleIds)
          .order('order_index', ascending: true)
          .execute();

      if (res.error != null) {
        throw createSupabaseError(res.error!);
      }

      final data = (res.data as List?) ?? [];
      for (final raw in data) {
        final row = SupabaseBundlePatchRow.fromJson(
          (raw as Map).cast<String, dynamic>(),
        );
        final current = patchMap[row.bundleId] ?? [];
        current.add(row);
        patchMap[row.bundleId] = current;
      }
      return patchMap;
    }

    return _SupabaseDatabasePlugin(
      supabase: supabase,
      fetchPatchMap: fetchPatchMap,
    );
  },
);

class _SupabaseDatabasePlugin implements AbstractDatabasePlugin {
  final SupabaseClientLike supabase;
  final Future<Map<String, List<SupabaseBundlePatchRow>>> Function(
    List<String> bundleIds,
  ) fetchPatchMap;

  _SupabaseDatabasePlugin({
    required this.supabase,
    required this.fetchPatchMap,
  });

  @override
  bool get supportsCursorPagination => false;

  @override
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args) async {
    final channel = args.channel;
    final minBundleId = args.minBundleId;

    if (args.updateStrategy == UpdateStrategy.appVersion) {
      final appArgs = args as AppVersionGetBundlesArgs;
      final targetRes = await supabase.rpc(
        'get_target_app_version_list',
        params: {
          'app_platform': appArgs.platform.value,
          'min_bundle_id': minBundleId,
        },
      );
      if (targetRes.error != null) {
        throw createSupabaseError(targetRes.error!);
      }
      final targetAppVersionList = filterCompatibleAppVersions(
        ((targetRes.data as List?) ?? [])
            .map((row) =>
                _SupabaseTargetAppVersionRow((row as Map)['target_app_version']))
            .where((row) => row.targetAppVersion != null)
            .map((row) => row.targetAppVersion!)
            .toList(),
        appArgs.appVersion,
      );

      final res = await supabase.rpc(
        'get_update_info_by_app_version',
        params: {
          'app_platform': appArgs.platform.value,
          'app_version': appArgs.appVersion,
          'bundle_id': appArgs.bundleId,
          'min_bundle_id': minBundleId,
          'target_channel': channel,
          'target_app_version_list': targetAppVersionList,
          'cohort': appArgs.cohort,
        },
      );
      if (res.error != null) {
        throw createSupabaseError(res.error!);
      }
      final list = (res.data as List?) ?? [];
      if (list.isEmpty) return null;
      return mapUpdateInfoRow(_rowToUpdateInfo(list.first));
    }

    final fpArgs = args as FingerprintGetBundlesArgs;
    final res = await supabase.rpc(
      'get_update_info_by_fingerprint_hash',
      params: {
        'app_platform': fpArgs.platform.value,
        'bundle_id': fpArgs.bundleId,
        'min_bundle_id': minBundleId,
        'target_channel': channel,
        'target_fingerprint_hash': fpArgs.fingerprintHash,
        'cohort': fpArgs.cohort,
      },
    );
    if (res.error != null) {
      throw createSupabaseError(res.error!);
    }
    final list = (res.data as List?) ?? [];
    if (list.isEmpty) return null;
    return mapUpdateInfoRow(_rowToUpdateInfo(list.first));
  }

  _SupabaseUpdateInfoRow _rowToUpdateInfo(Object raw) {
    final row = (raw as Map).cast<String, dynamic>();
    return _SupabaseUpdateInfoRow(
      id: row['id'] as String,
      shouldForceUpdate: row['should_force_update'] as bool,
      message: row['message'] as String?,
      status: row['status'] as String,
      storageUri: row['storage_uri'] as String?,
      fileHash: row['file_hash'] as String?,
    );
  }

  @override
  Future<Bundle?> getBundleById(String bundleId) async {
    final results = await Future.wait([
      supabase
          .from('bundles')
          .select(bundleSelectColumns)
          .eq('id', bundleId)
          .single()
          .execute(),
      fetchPatchMap([bundleId]),
    ]);

    final res = results[0] as SupabaseResponseLike;
    if (res.data == null || res.error != null) return null;
    final row = SupabaseBundleRow.fromJson(
      (res.data as Map).cast<String, dynamic>(),
    );
    final patches = (results[1] as Map<String, List<SupabaseBundlePatchRow>>)[bundleId] ?? [];
    return mapRowToBundle(row, patches);
        }

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) async {
    final where = options.where;
    final limit = options.limit;
    final orderBy = options.orderBy ??
        const DatabaseBundleQueryOrder(direction: 'desc');
    final offset = options.offset ??
        (options.page != null ? (options.page! - 1) * limit : 0);

    if ((where?.targetAppVersionIn != null &&
            where!.targetAppVersionIn!.isEmpty) ||
        (where?.id?.ins != null && where!.id!.ins!.isEmpty)) {
      return Paginated(
        data: const [],
        pagination: calculatePagination(0, limit: limit, offset: offset),
      );
    }

    var countQuery = supabase
        .from('bundles')
        .select('*', count: true, head: true);
    countQuery = _applyWhereFilters(countQuery, where);

    final countRes = await countQuery.execute();
    final total = countRes.count ?? 0;

    var query = supabase
        .from('bundles')
        .select(bundleSelectColumns)
        .order('id', ascending: orderBy.direction == 'asc');
    query = _applyWhereFilters(query, where);

    if (limit > 0) query = query.limit(limit);
    if (offset > 0) query = query.range(offset, offset + limit - 1);

    final res = await query.execute();
    if (res.error != null) {
      throw createSupabaseError(res.error!);
    }
    final data = (res.data as List?) ?? [];
    final patchMap = await fetchPatchMap(
      data.map((b) => (b as Map)['id'] as String).toList(),
    );
    final bundles = data.map((b) {
      final row = SupabaseBundleRow.fromJson((b as Map).cast<String, dynamic>());
      return mapRowToBundle(row, patchMap[row.id] ?? []);
    }).toList();

    return Paginated(
      data: bundles,
      pagination: calculatePagination(total, limit: limit, offset: offset),
    );
  }

  SupabaseFilterBuilderLike _applyWhereFilters(
    SupabaseFilterBuilderLike query,
    DatabaseBundleQueryWhere? where,
  ) {
    if (where == null) return query;
    if (where.channel != null) {
      query = query.eq('channel', where.channel!);
    }
    if (where.platform != null) {
      query = query.eq('platform', where.platform!.value);
    }
    if (where.enabled != null) {
      query = query.eq('enabled', where.enabled!);
    }
    if (where.fingerprintHash != null) {
      query = where.fingerprintHash == null
          ? query.isFilter('fingerprint_hash', null)
          : query.eq('fingerprint_hash', where.fingerprintHash!);
    }
    if (where.targetAppVersion != null) {
      query = where.targetAppVersion == null
          ? query.isFilter('target_app_version', null)
          : query.eq('target_app_version', where.targetAppVersion!);
    }
    if (where.targetAppVersionIn != null) {
      query = query.in_('target_app_version', where.targetAppVersionIn!);
    }
    if (where.targetAppVersionNotNull == true) {
      query = query.not('target_app_version', 'is', null);
    }
    if (where.id != null) {
      if (where.id!.eq != null) query = query.eq('id', where.id!.eq!);
      if (where.id!.gt != null) query = query.gt('id', where.id!.gt!);
      if (where.id!.gte != null) query = query.gte('id', where.id!.gte!);
      if (where.id!.lt != null) query = query.lt('id', where.id!.lt!);
      if (where.id!.lte != null) query = query.lte('id', where.id!.lte!);
      if (where.id!.ins != null) {
        query = query.in_('id', where.id!.ins!);
      }
    }
    return query;
  }

  @override
  Future<List<String>> getChannels() async {
    final res = await supabase.rpc('get_channels');
    if (res.error != null) {
      throw createSupabaseError(res.error!);
    }
    final data = (res.data as List?) ?? [];
    return data
        .map((row) => (row as Map)['channel'] as String)
        .toList();
  }

  @override
  Future<void> commitBundle({
    required List<BundleChange> changedSets,
  }) async {
    if (changedSets.isEmpty) return;

    for (final op in changedSets) {
      if (op.operation == BundleChangeOperation.delete) {
        final id = op.data.id;
        final patchDelete = await supabase
            .from('bundle_patches')
            .delete()
            .eq('bundle_id', id)
            .execute();
        if (patchDelete.error != null) {
          throw StateError(
            'Failed to delete bundle patches: ${patchDelete.error}',
          );
        }
        final basePatchDelete = await supabase
            .from('bundle_patches')
            .delete()
            .eq('base_bundle_id', id)
            .execute();
        if (basePatchDelete.error != null) {
          throw StateError(
            'Failed to delete base bundle patches: ${basePatchDelete.error}',
          );
        }
        final deleteRes = await supabase
            .from('bundles')
            .delete()
            .eq('id', id)
            .execute();
        if (deleteRes.error != null) {
          throw StateError('Failed to delete bundle: ${deleteRes.error}');
        }
      } else {
        final bundle = op.data;
        final patchRows = bundleToPatchRows(bundle);
        final upsertRes = await supabase
            .from('bundles')
            .upsert(bundleToRow(bundle), onConflict: 'id');
        if (upsertRes is SupabaseResponseLike && upsertRes.error != null) {
          throw createSupabaseError(upsertRes.error!);
        } else if (upsertRes is Map && upsertRes['error'] != null) {
          throw createSupabaseError(upsertRes['error']!);
        }

        final patchDelete = await supabase
            .from('bundle_patches')
            .delete()
            .eq('bundle_id', bundle.id)
            .execute();
        if (patchDelete.error != null) {
          throw createSupabaseError(patchDelete.error!);
        }

        if (patchRows.isNotEmpty) {
          final patchUpsert = await supabase
              .from('bundle_patches')
              .upsert(patchRows.map((p) => p.toJson()).toList(),
                  onConflict: 'id');
          if (patchUpsert is SupabaseResponseLike && patchUpsert.error != null) {
            throw createSupabaseError(patchUpsert.error!);
          } else if (patchUpsert is Map && patchUpsert['error'] != null) {
            throw createSupabaseError(patchUpsert['error']!);
          }
        }
      }
    }
  }

  @override
  Future<void> onUnmount() async {}
}
