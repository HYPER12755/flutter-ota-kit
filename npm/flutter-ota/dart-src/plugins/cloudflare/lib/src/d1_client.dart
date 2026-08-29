import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:http/http.dart' show Client;

import 'd1_config.dart' show D1DatabaseConfig;

/// A thin client over a Cloudflare D1 database.
///
/// Mirrors the `cf.d1.database.query(databaseId, { account_id, sql, params })`
/// call from hot-updater's cloudflare plugin: each call issues a single SQL
/// statement with positional `?` parameters and returns the flattened result
/// rows as JSON maps.
abstract class D1ClientLike {
  const D1ClientLike();

  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic> params = const [],
  ]);
}

/// Real D1 client backed by the Cloudflare REST API.
class D1Client implements D1ClientLike {
  D1Client(this.config, {Client? http}) : _http = http ?? Client();

  final D1DatabaseConfig config;
  final Client _http;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic> params = const [],
  ]) async {
    final uri = Uri.https(
      'api.cloudflare.com',
      '/client/v4/accounts/${config.accountId}/d1/database/${config.databaseId}/query',
    );

    final response = await _http.post(
      uri,
      headers: {
        'Authorization': 'Bearer ${config.cloudflareApiToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'sql': sql, 'params': params}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Cloudflare D1 query failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final result = (decoded['result'] as List?) ?? const <dynamic>[];

    final rows = <Map<String, dynamic>>[];
    for (final page in result.cast<Map<String, dynamic>>()) {
      final pageResults = (page['results'] as List?) ?? const <dynamic>[];
      for (final row in pageResults) {
        rows.add((row as Map).cast<String, dynamic>());
      }
    }
    return rows;
  }
}
