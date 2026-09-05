import 'dart:convert' show jsonDecode;

import 'package:flutter_ota_kit_cloudflare/flutter_ota_kit_cloudflare.dart'
    show
        CloudflareWorkerDatabaseConfig,
        D1ClientLike,
        D1DatabaseConfig,
        cloudflareWorkerDatabase,
        d1Database;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show DatabasePlugin;

/// In-memory store backing [MockD1Client], mirroring the D1 tables.
class Store {
  final List<Map<String, dynamic>> bundleRows = [];
  final List<Map<String, dynamic>> patchRows = [];
}

/// Mock D1 client that emulates the SQL issued by `_D1DatabasePlugin`.
class MockD1Client implements D1ClientLike {
  MockD1Client(this.store);

  final Store store;

  bool _asBool(dynamic v) => v is bool ? v : (v as num? ?? 0) != 0;

  List<String> _asList(dynamic v) {
    final decoded = jsonDecode(v as String) as List;
    return decoded.cast<String>();
  }

  bool _match(Map<String, dynamic> row, String where, List<dynamic> params) {
    var p = 0;
    if (where.contains('channel = ?')) {
      if (row['channel'] != params[p++]) return false;
    }
    if (where.contains('platform = ?')) {
      if (row['platform'] != params[p++]) return false;
    }
    if (where.contains('enabled = ?')) {
      if ((_asBool(row['enabled']) ? 1 : 0) != params[p++]) return false;
    }
    if (where.contains('id IN (SELECT value FROM json_each(?))')) {
      if (!_asList(params[p++]).contains(row['id'])) return false;
    }
    if (where.contains('id = ?')) {
      if (row['id'] != params[p++]) return false;
    }
    if (where.contains('id > ?')) {
      if ((row['id'] as String).compareTo(params[p++] as String) <= 0) {
        return false;
      }
    }
    if (where.contains('id >= ?')) {
      if ((row['id'] as String).compareTo(params[p++] as String) < 0) {
        return false;
      }
    }
    if (where.contains('id < ?')) {
      if ((row['id'] as String).compareTo(params[p++] as String) >= 0) {
        return false;
      }
    }
    if (where.contains('id <= ?')) {
      if ((row['id'] as String).compareTo(params[p++] as String) > 0) {
        return false;
      }
    }
    if (where.contains('target_app_version IS NOT NULL') &&
        !where.contains('target_app_version =')) {
      if (row['target_app_version'] == null) return false;
    }
    if (where.contains('target_app_version IS NULL')) {
      if (row['target_app_version'] != null) return false;
    }
    if (where.contains('target_app_version = ?')) {
      if (row['target_app_version'] != params[p++]) return false;
    }
    if (where.contains(
      'target_app_version IN (SELECT value FROM json_each(?))',
    )) {
      if (!_asList(params[p++]).contains(row['target_app_version'])) {
        return false;
      }
    }
    if (where.contains('fingerprint_hash IS NULL')) {
      if (row['fingerprint_hash'] != null) return false;
    }
    if (where.contains('fingerprint_hash = ?')) {
      if (row['fingerprint_hash'] != params[p++]) return false;
    }
    return true;
  }

  List<Map<String, dynamic>> _selectBundles(String sql, List<dynamic> params) {
    final fromIdx = sql.indexOf('FROM bundles') + 'FROM bundles'.length;
    var endIdx = sql.length;
    final orderIdx = sql.indexOf('ORDER BY id');
    if (orderIdx != -1) endIdx = orderIdx;
    final whereClause = sql.substring(fromIdx, endIdx);
    final whereParamCount = '?'.allMatches(whereClause).length;
    final whereParams = params.sublist(0, whereParamCount);

    final filtered = store.bundleRows
        .where((row) => _match(row, whereClause, whereParams))
        .toList();

    final descending = !sql.contains('ORDER BY id ASC');
    filtered.sort(
      (a, b) => descending
          ? (b['id'] as String).compareTo(a['id'] as String)
          : (a['id'] as String).compareTo(b['id'] as String),
    );

    if (sql.contains('LIMIT ?')) {
      final limit = params[whereParamCount] as int;
      final offset = params[whereParamCount + 1] as int;
      final start = offset.clamp(0, filtered.length);
      final end = (offset + limit).clamp(0, filtered.length);
      return filtered.sublist(start, end);
    }
    return filtered;
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic> params = const [],
  ]) async {
    if (sql.contains('SELECT COUNT(*)')) {
      final fromIdx = sql.indexOf('FROM bundles') + 'FROM bundles'.length;
      final whereClause = sql.substring(fromIdx);
      final total = store.bundleRows
          .where((row) => _match(row, whereClause, params))
          .length;
      return [
        {'total': total},
      ];
    }

    if (sql.contains('SELECT channel FROM bundles')) {
      final channels = {
        for (final row in store.bundleRows) row['channel'] as String,
      };
      return [
        for (final c in channels) {'channel': c},
      ];
    }

    if (sql.contains('SELECT target_app_version FROM bundles')) {
      final channel = params[0] as String;
      final platform = params[1] as String;
      final minId = params[2] as String;
      return [
        for (final row in store.bundleRows)
          if (row['channel'] == channel &&
              row['platform'] == platform &&
              _asBool(row['enabled']) &&
              (row['id'] as String).compareTo(minId) >= 0 &&
              row['target_app_version'] != null)
            {'target_app_version': row['target_app_version'] as String},
      ];
    }

    if (sql.contains('SELECT * FROM bundle_patches')) {
      final ids = _asList(params[0]);
      final rows = store.patchRows
          .where((row) => ids.contains(row['bundle_id']))
          .toList();
      rows.sort(
        (a, b) =>
            (a['order_index'] as num).compareTo(b['order_index'] as num) +
            (a['base_bundle_id'] as String).compareTo(
              b['base_bundle_id'] as String,
            ),
      );
      return rows;
    }

    if (sql.contains('SELECT * FROM bundles')) {
      return _selectBundles(sql, params);
    }

    if (sql.contains('INSERT OR REPLACE INTO bundles')) {
      final row = <String, dynamic>{
        'id': params[0],
        'channel': params[1],
        'enabled': params[2],
        'should_force_update': params[3],
        'file_hash': params[4],
        'git_commit_hash': params[5],
        'message': params[6],
        'platform': params[7],
        'target_app_version': params[8],
        'storage_uri': params[9],
        'fingerprint_hash': params[10],
        'metadata': params[11],
        'manifest_storage_uri': params[12],
        'manifest_file_hash': params[13],
        'asset_base_storage_uri': params[14],
        'rollout_cohort_count': params[15],
        'target_cohorts': params[16],
      };
      store.bundleRows.removeWhere((r) => r['id'] == row['id']);
      store.bundleRows.add(row);
      return const [];
    }

    if (sql.contains('INSERT OR REPLACE INTO bundle_patches')) {
      final row = <String, dynamic>{
        'id': params[0],
        'bundle_id': params[1],
        'base_bundle_id': params[2],
        'base_file_hash': params[3],
        'patch_file_hash': params[4],
        'patch_storage_uri': params[5],
        'order_index': params[6],
      };
      store.patchRows.removeWhere((r) => r['id'] == row['id']);
      store.patchRows.add(row);
      return const [];
    }

    if (sql.contains('DELETE FROM bundles')) {
      final id = params[0];
      store.bundleRows.removeWhere((r) => r['id'] == id);
      store.patchRows.removeWhere(
        (r) => r['bundle_id'] == id || r['base_bundle_id'] == id,
      );
      return const [];
    }

    if (sql.contains('DELETE FROM bundle_patches')) {
      final id = params[0];
      if (sql.contains('base_bundle_id')) {
        store.patchRows.removeWhere((r) => r['base_bundle_id'] == id);
      } else {
        store.patchRows.removeWhere((r) => r['bundle_id'] == id);
      }
      return const [];
    }

    return const [];
  }
}

/// Build a [D1DatabaseConfig] wired to an in-memory [Store].
D1DatabaseConfig mockConfig(Store store) => D1DatabaseConfig(
  databaseId: 'test-db',
  accountId: 'test-account',
  cloudflareApiToken: 'test-token',
  clientFactory: (_) => MockD1Client(store),
);

/// Construct the plugin with an in-memory store.
DatabasePlugin newPlugin(Store store) => d1Database(mockConfig(store))();

/// Construct the Workers D1 variant with an in-memory store.
DatabasePlugin newWorkerPlugin(Store store) => cloudflareWorkerDatabase(
  CloudflareWorkerDatabaseConfig(getDb: () => MockD1Client(store)),
)();
