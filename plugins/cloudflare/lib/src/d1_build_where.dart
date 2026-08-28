import 'dart:convert' show jsonEncode;

import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show DatabaseBundleQueryWhere;

/// Result of building a WHERE clause: SQL fragment plus positional params.
class _BuildWhereResult {
  const _BuildWhereResult(this.sql, this.params);

  final String sql;
  final List<dynamic> params;
}

/// Build a SQLite WHERE clause with positional `?` params, mirroring
/// `buildWhereClause` from hot-updater's `d1Database.ts`.
_BuildWhereResult buildWhereClause(DatabaseBundleQueryWhere conditions) {
  final clauses = <String>[];
  final params = <dynamic>[];

  String jsonEachIn(String columnName, List<String> values) {
    if (values.isEmpty) return '1 = 0';
    params.add(jsonEncode(values));
    return '$columnName IN (SELECT value FROM json_each(?))';
  }

  if (conditions.channel != null) {
    clauses.add('channel = ?');
    params.add(conditions.channel);
  }

  if (conditions.platform != null) {
    clauses.add('platform = ?');
    params.add(conditions.platform!.value);
  }

  if (conditions.enabled != null) {
    clauses.add('enabled = ?');
    params.add(conditions.enabled! ? 1 : 0);
  }

  if (conditions.id?.ins != null) {
    clauses.add(jsonEachIn('id', conditions.id!.ins!));
  }

  if (conditions.id?.eq != null) {
    clauses.add('id = ?');
    params.add(conditions.id!.eq);
  }

  if (conditions.id?.gt != null) {
    clauses.add('id > ?');
    params.add(conditions.id!.gt);
  }

  if (conditions.id?.gte != null) {
    clauses.add('id >= ?');
    params.add(conditions.id!.gte);
  }

  if (conditions.id?.lt != null) {
    clauses.add('id < ?');
    params.add(conditions.id!.lt);
  }

  if (conditions.id?.lte != null) {
    clauses.add('id <= ?');
    params.add(conditions.id!.lte);
  }

  if (conditions.targetAppVersionNotNull == true) {
    clauses.add('target_app_version IS NOT NULL');
  }

  if (conditions.targetAppVersion != null) {
    clauses.add('target_app_version = ?');
    params.add(conditions.targetAppVersion);
  }

  if (conditions.targetAppVersionIn != null) {
    clauses.add(
      jsonEachIn('target_app_version', conditions.targetAppVersionIn!),
    );
  }

  if (conditions.fingerprintHash != null) {
    clauses.add('fingerprint_hash = ?');
    params.add(conditions.fingerprintHash);
  }

  final whereClause =
      clauses.isNotEmpty ? ' WHERE ${clauses.join(' AND ')}' : '';
  return _BuildWhereResult(whereClause, params);
}
