import 'dart:typed_data';

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';

import 'package:flutter_ota_kit_postgres/flutter_ota_kit_postgres.dart';

/// In-memory store backing [MockPostgresClient]. Mirrors the `bundles` and
/// `bundle_patches` tables (snake_case row maps).
class Store {
  Store({List<Bundle>? seed}) {
    if (seed != null) {
      for (final b in seed) {
        bundleRows.add(bundleToRowValues(b));
        bundlePatchRows.addAll(bundleToPatchRows(b));
      }
    }
  }

  final List<Map<String, dynamic>> bundleRows = [];
  final List<Map<String, dynamic>> bundlePatchRows = [];
  final Map<String, List<int>> storageObjects = {};

  Map<String, dynamic>? bundleRowById(String id) => bundleRows
      .where((row) => row['id'] == id)
      .cast<Map<String, dynamic>?>()
      .firstOrNull;
}

/// Mock [PostgresClientLike] that emulates the queries the plugin issues
/// against an in-memory [Store]. Faithful enough to exercise the plugin's
/// SQL building, row mapping, transactions, and RPC calls without a live DB.
class MockPostgresClient implements PostgresClientLike {
  MockPostgresClient(this.store);

  final Store store;
  final List<String> executedSqls = [];
  final List<Map<String, dynamic>> executedParams = [];

  @override
  Future<List<Map<String, dynamic>>> execute(
    String sql,
    Map<String, dynamic> parameters,
  ) async {
    executedSqls.add(sql);
    executedParams.add(parameters);
    return _handle(sql, parameters);
  }

  @override
  Future<T> runTx<T>(Future<T> Function(PostgresClientLike tx) fn) async {
    return fn(_TxClient(this));
  }

  @override
  Future<void> close() async {}

  List<Map<String, dynamic>> _handle(
    String sql,
    Map<String, dynamic> params,
  ) {
    if (sql.contains('get_target_app_version_list')) {
      return _targetAppVersionList(params);
    }
    if (sql.contains('get_update_info_by_app_version')) {
      return _updateInfoByAppVersion(params);
    }
    if (sql.contains('get_update_info_by_fingerprint_hash')) {
      return _updateInfoByFingerprint(params);
    }
    if (sql.contains('GROUP BY channel')) return _channels();
    if (sql.contains('COUNT(*)')) return _count(sql, params);
    if (sql.contains('FROM bundle_patches') && sql.contains('ANY')) {
      return _patchesForIds(params);
    }
    if (sql.contains('INSERT INTO bundle_patches')) {
      _upsertPatch(params);
      return [];
    }
    if (sql.contains('INSERT INTO bundles')) {
      _upsertBundle(params);
      return [];
    }
    if (sql.contains('DELETE FROM bundle_patches')) {
      _deletePatches(sql, params);
      return [];
    }
    if (sql.contains('DELETE FROM bundles')) {
      return _deleteBundle(sql, params);
    }
    if (sql.contains('SELECT * FROM bundles')) {
      return _selectBundles(sql, params);
    }
    if (sql.contains('flutter_ota_kit_storage')) {
      return _handleStorage(sql, params);
    }
    return [];
  }

  List<Map<String, dynamic>> _handleStorage(
    String sql,
    Map<String, dynamic> params,
  ) {
    if (sql.contains('INSERT INTO flutter_ota_kit_storage')) {
      final key = params['@key'] as String;
      final data = params['@data'];
      store.storageObjects[key] = data is List<int>
          ? data
          : data is Uint8List
              ? data
              : <int>[];
      return [];
    }
    if (sql.contains('SELECT 1 FROM flutter_ota_kit_storage')) {
      final key = params['@key'] as String;
      return store.storageObjects.containsKey(key) ? [{'1': 1}] : [];
    }
    if (sql.contains('DELETE FROM flutter_ota_kit_storage')) {
      final key = params['@key'] as String;
      store.storageObjects.remove(key);
      return [];
    }
    if (sql.contains('SELECT data FROM flutter_ota_kit_storage')) {
      final key = params['@key'] as String;
      final data = store.storageObjects[key];
      if (data == null) return [];
      return [
        {'data': Uint8List.fromList(data)},
      ];
    }
    if (sql.contains('SELECT key, octet_length(data)')) {
      final prefix = (params['@prefix'] as String?) ?? '';
      return store.storageObjects.keys
          .where((k) => k.startsWith(prefix))
          .map((k) => {
                'key': k,
                'size': store.storageObjects[k]!.length,
              })
          .toList();
    }
    return [];
  }

  dynamic _paramAfter(String sql, String token, Map<String, dynamic> params) {
    final idx = sql.indexOf(token);
    if (idx < 0) return null;
    final rest = sql.substring(idx + token.length).trim();
    final match = RegExp(r'@(\w+)').firstMatch(rest);
    if (match == null) return null;
    final name = match.group(1)!;
    return params['@$name'] ?? params[name];
  }

  List<Map<String, dynamic>> _filterBundles(
    String sql,
    Map<String, dynamic> params,
  ) {
    return store.bundleRows.where((row) {
      final channel = _paramAfter(sql, 'channel =', params);
      if (channel != null && row['channel'] != channel) return false;
      final platform = _paramAfter(sql, 'platform =', params);
      if (platform != null && row['platform'] != platform) return false;
      final enabled = _paramAfter(sql, 'enabled =', params);
      if (enabled != null && row['enabled'] != enabled) return false;
      final target = _paramAfter(sql, 'target_app_version =', params);
      if (target != null && row['target_app_version'] != target) return false;
      final idEq = _paramAfter(sql, 'id =', params);
      if (idEq != null && row['id'] != idEq) return false;
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _selectBundles(
    String sql,
    Map<String, dynamic> params,
  ) {
    var rows = _filterBundles(sql, params);

    if (sql.contains('ORDER BY id asc')) {
      rows = rows.toList()..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    } else {
      rows = rows.toList()
        ..sort((a, b) => (b['id'] as String).compareTo(a['id'] as String));
    }

    final limit = params['@limit'] as int?;
    final offset = params['@offset'] as int? ?? 0;
    if (limit != null && limit > 0) {
      final end = (offset + limit).clamp(0, rows.length);
      rows = rows.sublist(offset.clamp(0, rows.length), end);
    } else if (offset > 0) {
      rows = rows.sublist(offset.clamp(0, rows.length));
    }
    return rows;
  }

  List<Map<String, dynamic>> _count(String sql, Map<String, dynamic> params) {
    return [
      {'total': _filterBundles(sql, params).length},
    ];
  }

  List<Map<String, dynamic>> _channels() {
    final channels = store.bundleRows.map((r) => r['channel'] as String).toSet().toList();
    return channels.map((c) => {'channel': c}).toList();
  }

  List<Map<String, dynamic>> _patchesForIds(Map<String, dynamic> params) {
    final ids = (params['bundle_ids'] as List).cast<String>();
    return store.bundlePatchRows.where((p) => ids.contains(p['bundle_id'])).toList();
  }

  void _upsertBundle(Map<String, dynamic> params) {
    final row = <String, dynamic>{};
    params.forEach((k, v) => row[k] = v);
    final existing = store.bundleRows.indexWhere((r) => r['id'] == row['id']);
    if (existing >= 0) {
      store.bundleRows[existing] = row;
    } else {
      store.bundleRows.add(row);
    }
  }

  void _upsertPatch(Map<String, dynamic> params) {
    final row = <String, dynamic>{};
    params.forEach((k, v) => row[k] = v);
    final existing = store.bundlePatchRows.indexWhere((r) => r['id'] == row['id']);
    if (existing >= 0) {
      store.bundlePatchRows[existing] = row;
    } else {
      store.bundlePatchRows.add(row);
    }
  }

  void _deletePatches(String sql, Map<String, dynamic> params) {
    final id = params['@p0'] ?? params['p0'];
    if (sql.contains('base_bundle_id')) {
      store.bundlePatchRows.removeWhere((p) => p['base_bundle_id'] == id);
    } else {
      store.bundlePatchRows.removeWhere((p) => p['bundle_id'] == id);
    }
  }

  List<Map<String, dynamic>> _deleteBundle(
    String sql,
    Map<String, dynamic> params,
  ) {
    final id = params['@p0'] ?? params['p0'];
    final existed = store.bundleRows.any((r) => r['id'] == id);
    store.bundleRows.removeWhere((r) => r['id'] == id);
    store.bundlePatchRows.removeWhere((p) => p['bundle_id'] == id);
    return existed ? [{'id': id}] : [];
  }

  List<Map<String, dynamic>> _targetAppVersionList(Map<String, dynamic> params) {
    final platform = params['app_platform'];
    final min = params['min_bundle_id'] as String? ?? '';
    final versions = store.bundleRows
        .where((r) => r['platform'] == platform && (r['id'] as String).compareTo(min) >= 0)
        .map((r) => r['target_app_version'])
        .where((v) => v != null)
        .toSet()
        .cast<String>()
        .toList();
    return versions.map((v) => {'target_app_version': v}).toList();
  }

  Map<String, dynamic>? _newestMatch(
    bool Function(Map<String, dynamic> row) predicate,
  ) {
    final matches = store.bundleRows.where(predicate).toList()
      ..sort((a, b) => (b['id'] as String).compareTo(a['id'] as String));
    return matches.isEmpty ? null : matches.first;
  }

  List<Map<String, dynamic>> _updateInfoByAppVersion(Map<String, dynamic> params) {
    final platform = params['app_platform'];
    final channel = params['target_channel'];
    final min = params['min_bundle_id'] as String? ?? '';
    final list = (params['target_app_version_list'] as List?)?.cast<String>() ?? [];
    final row = _newestMatch((r) =>
        r['platform'] == platform &&
        r['enabled'] == true &&
        r['channel'] == channel &&
        (r['id'] as String).compareTo(min) >= 0 &&
        list.contains(r['target_app_version']));
    if (row == null) return [];
    return [_infoRow(row)];
  }

  List<Map<String, dynamic>> _updateInfoByFingerprint(Map<String, dynamic> params) {
    final platform = params['app_platform'];
    final channel = params['target_channel'];
    final min = params['min_bundle_id'] as String? ?? '';
    final fp = params['target_fingerprint_hash'];
    final row = _newestMatch((r) =>
        r['platform'] == platform &&
        r['enabled'] == true &&
        r['channel'] == channel &&
        (r['id'] as String).compareTo(min) >= 0 &&
        r['fingerprint_hash'] == fp);
    if (row == null) return [];
    return [_infoRow(row)];
  }

  Map<String, dynamic> _infoRow(Map<String, dynamic> row) => {
        'id': row['id'],
        'should_force_update': row['should_force_update'],
        'message': row['message'],
        'status': 'UPDATE',
        'storage_uri': row['storage_uri'],
        'file_hash': row['file_hash'],
      };
}

class _TxClient implements PostgresClientLike {
  _TxClient(this._parent);

  final MockPostgresClient _parent;

  @override
  Future<List<Map<String, dynamic>>> execute(
    String sql,
    Map<String, dynamic> parameters,
  ) =>
      _parent.execute(sql, parameters);

  @override
  Future<T> runTx<T>(Future<T> Function(PostgresClientLike tx) fn) =>
      throw UnsupportedError('Nested transactions are not supported');

  @override
  Future<void> close() async {}
}

/// Build a [PostgresConfig] wired to [MockPostgresClient].
PostgresConfig mockPostgresConfig(Store store) => PostgresConfig(
      host: 'mock',
      database: 'mock',
      clientFactory: (_) => MockPostgresClient(store),
    );

/// Create a [DatabasePlugin] backed by the mock store.
DatabasePlugin newPlugin({Store? store}) {
  final s = store ?? Store();
  final plugin = postgresDatabase(mockPostgresConfig(s))();
  return plugin;
}
