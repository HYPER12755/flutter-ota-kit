/// Faithful port of hot-updater `plugins/postgres/src/postgres.ts`.
library;

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show Bundle, UpdateInfo;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show
        AbstractDatabasePlugin,
        BundleChange,
        BundleChangeOperation,
        DatabaseBundleQueryOptions,
        DatabaseBundleQueryOrder,
        DatabaseBundleQueryWhere,
        DatabasePlugin,
        DatabasePluginHooks,
        GetBundlesArgs,
        Paginated,
        calculatePagination,
        createDatabasePlugin;

import 'postgres_bundle_mapper.dart';
import 'postgres_client.dart';
import 'postgres_config.dart';
import 'postgres_get_update_info.dart' as pg_ui;
import 'postgres_types.dart';

/// Postgres-backed [DatabasePlugin] factory.
///
/// Mirrors `postgres` from hot-updater: a `createDatabasePlugin` wrapper whose
/// inner factory builds a Postgres client and returns an [AbstractDatabasePlugin]
/// implementation talking to the `bundles` / `bundle_patches` tables and the
/// update-info RPCs.
DatabasePlugin Function() Function(
  PostgresConfig config, [
  DatabasePluginHooks? hooks,
]) postgresDatabase = createDatabasePlugin<PostgresConfig>(
  name: 'postgresDatabase',
  factory: (config) {
    final client = config.clientFactory != null
        ? config.clientFactory!(config)
        : PostgresClient.connect(config);

    Future<Map<String, List<PostgresBundlePatchRow>>> fetchPatchMap(
      List<String> bundleIds,
    ) async {
      final patchMap = <String, List<PostgresBundlePatchRow>>{};
      if (bundleIds.isEmpty) return patchMap;

      final rows = await client.execute(
        'SELECT * FROM bundle_patches '
        'WHERE bundle_id = ANY(@bundle_ids) ORDER BY order_index ASC',
        {'bundle_ids': bundleIds},
      );

      for (final raw in rows) {
        final row = PostgresBundlePatchRow.fromJson(raw);
        final current = patchMap[row.bundleId] ?? [];
        current.add(row);
        patchMap[row.bundleId] = current;
      }
      return patchMap;
    }

    return _PostgresDatabasePlugin(
      client: client,
      fetchPatchMap: fetchPatchMap,
    );
  },
);

/// Build a SQL `WHERE` fragment (with `@pN` placeholders) from [where].
(String where, Map<String, dynamic> params) _buildWhere(
  DatabaseBundleQueryWhere? where,
) {
  final conditions = <String>[];
  final params = <String, dynamic>{};
  if (where == null) return ('', params);

  var index = 0;
  String next() => '@p${index++}';

  void add(String sql, dynamic value) {
    final p = next();
    conditions.add(sql.replaceAll('?', p));
    params[p] = value;
  }

  if (where.channel != null) {
    add('channel = ?', where.channel);
  }
  if (where.platform != null) {
    add('platform = ?', where.platform!.value);
  }
  if (where.enabled != null) {
    add('enabled = ?', where.enabled);
  }
  if (where.fingerprintHash != null) {
    if (where.fingerprintHash == null) {
      conditions.add('fingerprint_hash IS NULL');
    } else {
      add('fingerprint_hash = ?', where.fingerprintHash);
    }
  }
  if (where.targetAppVersion != null) {
    if (where.targetAppVersion == null) {
      conditions.add('target_app_version IS NULL');
    } else {
      add('target_app_version = ?', where.targetAppVersion);
    }
  }
  if (where.targetAppVersionIn != null) {
    add('target_app_version = ANY(?)', where.targetAppVersionIn);
  }
  if (where.targetAppVersionNotNull == true) {
    conditions.add('target_app_version IS NOT NULL');
  }
  if (where.id != null) {
    final id = where.id!;
    if (id.eq != null) add('id = ?', id.eq);
    if (id.gt != null) add('id > ?', id.gt);
    if (id.gte != null) add('id >= ?', id.gte);
    if (id.lt != null) add('id < ?', id.lt);
    if (id.lte != null) add('id <= ?', id.lte);
    if (id.ins != null) add('id = ANY(?)', id.ins);
  }

  return (
    conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}',
    params,
  );
}

class _PostgresDatabasePlugin implements AbstractDatabasePlugin {
  final PostgresClientLike client;
  final Future<Map<String, List<PostgresBundlePatchRow>>> Function(
    List<String> bundleIds,
  ) fetchPatchMap;

  _PostgresDatabasePlugin({
    required this.client,
    required this.fetchPatchMap,
  });

  @override
  bool get supportsCursorPagination => false;

  @override
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args) =>
      pg_ui.getUpdateInfo(client, args);

  @override
  Future<Bundle?> getBundleById(String bundleId) async {
    final results = await Future.wait([
      client.execute(
        'SELECT * FROM bundles WHERE id = @p0',
        {'p0': bundleId},
      ),
      fetchPatchMap([bundleId]),
    ]);

    final data = results[0] as List<Map<String, dynamic>>;
    if (data.isEmpty) return null;
    final row = PostgresBundleRow.fromJson(data.first);
    final patches = (results[1] as Map<String, List<PostgresBundlePatchRow>>)[bundleId] ?? [];
    return mapRowToBundle(row, patches);
  }

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) async {
    final where = options.where;
    final limit = options.limit;
    final orderBy =
        options.orderBy ?? const DatabaseBundleQueryOrder(direction: 'desc');
    final offset =
        options.offset ?? (options.page != null ? (options.page! - 1) * limit : 0);

    if ((where?.targetAppVersionIn != null && where!.targetAppVersionIn!.isEmpty) ||
        (where?.id?.ins != null && where!.id!.ins!.isEmpty)) {
      return Paginated(
        data: const [],
        pagination: calculatePagination(0, limit: limit, offset: offset),
      );
    }

    final (whereSql, whereParams) = _buildWhere(where);

    final countRows = await client.execute(
      'SELECT COUNT(*) AS total FROM bundles $whereSql',
      whereParams,
    );
    final total = countRows.isEmpty
        ? 0
        : (countRows.first['total'] as num?)?.toInt() ?? 0;

    final selectParams = <String, dynamic>{...whereParams};
    if (limit > 0) selectParams['@limit'] = limit;
    if (offset > 0) selectParams['@offset'] = offset;

    final dataRows = await client.execute(
      'SELECT * FROM bundles $whereSql '
      'ORDER BY id ${orderBy.direction == 'asc' ? 'asc' : 'desc'}'
      '${limit > 0 ? ' LIMIT @limit' : ''}'
      '${offset > 0 ? ' OFFSET @offset' : ''}',
      selectParams,
    );

    final patchMap = await fetchPatchMap(
      dataRows.map((row) => row['id'] as String).toList(),
    );
    final bundles = dataRows.map((row) {
      final bundleRow = PostgresBundleRow.fromJson(row);
      return mapRowToBundle(bundleRow, patchMap[bundleRow.id] ?? []);
    }).toList();

    return Paginated(
      data: bundles,
      pagination: calculatePagination(total, limit: limit, offset: offset),
    );
  }

  @override
  Future<List<String>> getChannels() async {
    final rows = await client.execute(
      'SELECT channel FROM bundles GROUP BY channel',
      {},
    );
    return rows.map((row) => row['channel'] as String).toList();
  }

  @override
  Future<void> commitBundle({
    required List<BundleChange> changedSets,
  }) async {
    if (changedSets.isEmpty) return;

    await client.runTx((tx) async {
      for (final op in changedSets) {
        if (op.operation == BundleChangeOperation.delete) {
          await tx.execute(
            'DELETE FROM bundle_patches WHERE bundle_id = @p0',
            {'p0': op.data.id},
          );
          await tx.execute(
            'DELETE FROM bundle_patches WHERE base_bundle_id = @p0',
            {'p0': op.data.id},
          );
          final result = await tx.execute(
            'DELETE FROM bundles WHERE id = @p0 RETURNING id',
            {'p0': op.data.id},
          );
          if (result.isEmpty) {
            throw StateError('Bundle with id ${op.data.id} not found');
          }
        } else {
          final bundle = op.data;
          final values = bundleToRowValues(bundle);
          final columns = values.keys.toList();
          final insertCols = columns.join(', ');
          final placeholders =
              columns.map((c) => '@${c.replaceAll('.', '_')}').join(', ');
          final updateSets = columns
              .where((c) => c != 'id')
              .map((c) => '$c = EXCLUDED.$c')
              .join(', ');
          await tx.execute(
            'INSERT INTO bundles ($insertCols) VALUES ($placeholders) '
            'ON CONFLICT (id) DO UPDATE SET $updateSets',
            {for (final c in columns) c.replaceAll('.', '_'): values[c]},
          );

          await tx.execute(
            'DELETE FROM bundle_patches WHERE bundle_id = @p0',
            {'p0': bundle.id},
          );
          final patchRows = bundleToPatchRows(bundle);
          if (patchRows.isNotEmpty) {
            for (final pr in patchRows) {
              final patchCols = pr.keys.toList();
              final patchInsert = patchCols.join(', ');
              final patchPlaceholders =
                  patchCols.map((c) => '@${c.replaceAll('.', '_')}').join(', ');
              await tx.execute(
                'INSERT INTO bundle_patches ($patchInsert) '
                'VALUES ($patchPlaceholders) '
                'ON CONFLICT (id) DO UPDATE SET '
                '${patchCols.where((c) => c != 'id').map((c) => '$c = EXCLUDED.$c').join(', ')}',
                {for (final c in patchCols) c.replaceAll('.', '_'): pr[c]},
              );
            }
          }
        }
      }
    });
  }

  @override
  Future<void> onUnmount() async {
    await client.close();
  }
}
