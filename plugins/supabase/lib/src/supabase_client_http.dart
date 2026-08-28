/// Production adapter implementing [SupabaseClientLike] over the Supabase
/// REST (PostgREST) API using plain `http` calls.
///
/// This is the Dart equivalent of `@supabase/supabase-js`'s `createClient`:
/// it talks to the same REST endpoints the JS client would, so the plugin
/// logic stays identical regardless of transport.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'supabase_client_adapter.dart';

class _HttpResponse implements SupabaseResponseLike {
  @override
  final Object? data;
  @override
  final Object? error;
  @override
  final int? count;

  const _HttpResponse(this.data, this.error, this.count);
}

class _FilterBuilder implements SupabaseFilterBuilderLike {
  final String _baseUrl;
  final String _table;
  final Map<String, String> _query;
  final Map<String, String> _headers;
  final String _method;
  final Object? _body;

  _FilterBuilder({
    required String baseUrl,
    required String table,
    required Map<String, String> headers,
    Map<String, String>? query,
    String method = 'GET',
    Object? body,
  })  : _baseUrl = baseUrl,
        _table = table,
        _headers = headers,
        _query = query ?? {},
        _method = method,
        _body = body;

  @override
  SupabaseFilterBuilderLike eq(String column, Object? value) =>
      _addFilter(column, 'eq', value);

  @override
  SupabaseFilterBuilderLike gt(String column, Object? value) =>
      _addFilter(column, 'gt', value);

  @override
  SupabaseFilterBuilderLike gte(String column, Object? value) =>
      _addFilter(column, 'gte', value);

  @override
  SupabaseFilterBuilderLike lt(String column, Object? value) =>
      _addFilter(column, 'lt', value);

  @override
  SupabaseFilterBuilderLike lte(String column, Object? value) =>
      _addFilter(column, 'lte', value);

  @override
  SupabaseFilterBuilderLike in_(String column, List<Object?> values) {
    _query[column] = 'in.(${values.join(',')})';
    return this;
  }

  @override
  SupabaseFilterBuilderLike isFilter(String column, Object? value) {
    _query[column] = 'is.${value ?? 'null'}';
    return this;
  }

  @override
  SupabaseFilterBuilderLike not(
    String column,
    String operator,
    Object? value,
  ) {
    _query[column] = 'not.$operator.${_enc(value)}';
    return this;
  }

  @override
  SupabaseFilterBuilderLike order(String column, {bool? ascending}) {
    _query['order'] = ascending == false ? '$column.desc' : '$column.asc';
    return this;
  }

  @override
  SupabaseFilterBuilderLike limit(int value) {
    _query['limit'] = value.toString();
    return this;
  }

  @override
  SupabaseFilterBuilderLike range(int from, int to) {
    _headers['Range'] = '$from-$to';
    _headers['Range-Unit'] = 'items';
    return this;
  }

  @override
  SupabaseFilterBuilderLike single() {
    _headers['Accept'] = 'application/vnd.pgrst.object+json';
    return this;
  }

  SupabaseFilterBuilderLike _addFilter(
    String column,
    String op,
    Object? value,
  ) {
    _query[column] = '$op.${_enc(value)}';
    return this;
  }

  String _enc(Object? value) => value == null ? 'null' : value.toString();

  @override
  Future<SupabaseResponseLike> execute() async {
    final uri = Uri.parse('$_baseUrl/rest/v1/$_table')
        .replace(queryParameters: _query.isEmpty ? null : _query);
    final headers = <String, String>{
      ..._headers,
      if (_method != 'GET' && _body != null)
        'Content-Type': 'application/json',
    };

    late http.Response res;
    switch (_method) {
      case 'DELETE':
        res = await http.delete(uri, headers: headers);
        break;
      case 'POST':
        res = await http.post(
          uri,
          headers: headers,
          body: _body == null ? null : jsonEncode(_body),
        );
        break;
      case 'PATCH':
        res = await http.patch(
          uri,
          headers: headers,
          body: _body == null ? null : jsonEncode(_body),
        );
        break;
      default:
        res = await http.get(uri, headers: headers);
    }

    if (res.statusCode >= 400) {
      return _HttpResponse(null, jsonDecode(res.body), null);
    }

    final body = res.body.isEmpty ? null : jsonDecode(res.body);
    final countHeader = res.headers['content-range'];
    int? count;
    if (countHeader != null) {
      final slash = countHeader.indexOf('/');
      if (slash >= 0 && slash + 1 < countHeader.length) {
        count = int.tryParse(countHeader.substring(slash + 1));
      }
    }
    return _HttpResponse(body, null, count);
  }
}

class _QueryBuilder implements SupabaseQueryBuilderLike {
  final String _baseUrl;
  final String _table;
  final Map<String, String> _headers;

  _QueryBuilder(this._baseUrl, this._table, this._headers);

  @override
  SupabaseFilterBuilderLike select(
    String columns, {
    bool? count,
    bool? head,
  }) {
    final headers = <String, String>{..._headers};
    if (count == true) headers['Prefer'] = 'count=exact';
    if (head == true) headers['Range'] = '0-0';
    return _FilterBuilder(
      baseUrl: _baseUrl,
      table: _table,
      headers: headers,
      query: {'select': columns},
    );
  }

  @override
  SupabaseFilterBuilderLike delete() => _FilterBuilder(
        baseUrl: _baseUrl,
        table: _table,
        headers: _headers,
        method: 'DELETE',
      );

  @override
  Future<dynamic> upsert(dynamic values, {String? onConflict}) async {
    final uri = Uri.parse('$_baseUrl/rest/v1/$_table').replace(
      queryParameters: onConflict != null
          ? {'on_conflict': onConflict}
          : null,
    );
    final headers = <String, String>{
      ..._headers,
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates',
    };
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(values),
    );
    if (res.statusCode >= 400) {
      return _HttpResponse(null, jsonDecode(res.body), null);
    }
    return _HttpResponse(
      res.body.isEmpty ? null : jsonDecode(res.body),
      null,
      null,
    );
  }
}

class _StorageBucket implements SupabaseStorageBucketLike {
  final String _baseUrl;
  final String _bucket;
  final Map<String, String> _headers;

  _StorageBucket(this._baseUrl, this._bucket, this._headers);

  @override
  Future<SupabaseSignedUrlResult> createSignedUrl(
    String path,
    int expiresIn,
  ) async {
    final uri = Uri.parse('$_baseUrl/storage/v1/object/sign/$_bucket/$path');
    final res = await http.post(
      uri,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'expiresIn': expiresIn}),
    );
    if (res.statusCode >= 400) {
      return _MockSignedUrlResult(null, jsonDecode(res.body));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final signed = body['signedURL'] as String?;
    // Supabase returns a relative path ("/object/sign/...?token=..."); make it
    // absolute against the project base URL.
    return _MockSignedUrlResult(
      signed == null ? null : '$_baseUrl/storage/v1$signed',
      null,
    );
  }

  @override
  Future<SupabaseSignedUrlListResult> createSignedUrls(
    List<String> paths,
    int expiresIn,
  ) async {
    final uri = Uri.parse('$_baseUrl/storage/v1/object/sign/$_bucket');
    final res = await http.post(
      uri,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'expiresIn': expiresIn,
        'paths': paths,
      }),
    );
    if (res.statusCode >= 400) {
      return _MockSignedUrlListResult(null, jsonDecode(res.body));
    }
    final body = jsonDecode(res.body) as List<dynamic>;
    return _MockSignedUrlListResult(
      body
          .map((e) => _MockSignedUrlResult(
                // Supabase returns a relative path; make it absolute against
                // the project base URL, matching [createSignedUrl].
                e['signedURL'] == null
                    ? null
                    : '$_baseUrl/storage/v1${e['signedURL'] as String}',
                e['error'] as String?,
              ))
          .toList(),
      null,
    );
  }

  Future<void> _ensureBucket() async {
    final res = await http.post(
      Uri.parse('$_baseUrl/storage/v1/bucket'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'name': _bucket, 'public': true}),
    );
    // 400/409 just mean it already exists — that's fine.
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final msg = (body['message'] ?? body['error'] ?? '').toString();
      if (!msg.contains('already exists') && res.statusCode != 409) {
        throw StateError('Failed to create bucket "$_bucket": $msg');
      }
    }
  }

  @override
  Future<SupabaseUploadResult> upload(
    String path,
    List<int> fileBytes, {
    String? contentType,
    String? cacheControl,
  }) async {
    Future<_MockUploadResult> doUpload() async {
      final uri = Uri.parse('$_baseUrl/storage/v1/object/$_bucket/$path');
      final res = await http.post(
        uri,
        headers: {
          ..._headers,
          'Content-Type': contentType ?? 'application/octet-stream',
          if (cacheControl != null) 'Cache-Control': cacheControl,
        },
        body: fileBytes,
      );
      if (res.statusCode >= 400) {
        return _MockUploadResult(null, jsonDecode(res.body));
      }
      return _MockUploadResult(jsonDecode(res.body), null);
    }

    final first = await doUpload();
    if (first.error != null) {
      final msg =
          (first.error is Map ? (first.error as Map)['message'] : first.error)
              .toString();
      if (msg.contains('Bucket not found')) {
        await _ensureBucket();
        return doUpload();
      }
    }
    return first;
  }

  @override
  Future<SupabaseRemoveResult> remove(List<String> paths) async {
    final uri = Uri.parse('$_baseUrl/storage/v1/object/$_bucket');
    final res = await http.delete(
      uri,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'prefixes': paths}),
    );
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return _MockRemoveResult(null, body['message'] as String?);
    }
    return _MockRemoveResult(jsonDecode(res.body), null);
  }

  @override
  Future<SupabaseExistsResult> exists(String path) async {
    final uri = Uri.parse(
      '$_baseUrl/storage/v1/object/$_bucket/$path',
    ).replace(queryParameters: {'_method': 'HEAD'});
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 404) {
      return _MockExistsResult(false, null);
    }
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return _MockExistsResult(null, body['message'] as String?);
    }
    return _MockExistsResult(true, null);
  }

  @override
  Future<SupabaseDownloadResult> download(String path) async {
    final uri = Uri.parse('$_baseUrl/storage/v1/object/$_bucket/$path');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return _MockDownloadResult(null, body['message'] as String?);
    }
    return _MockDownloadResult(res.bodyBytes, null);
  }

  @override
  Future<SupabaseListResult> list([String? prefix]) async {
    final uri = Uri.parse('$_baseUrl/storage/v1/object/list/$_bucket');
    final res = await http.post(
      uri,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'prefix': prefix ?? ''}),
    );
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return _MockListResult(null, body['message'] as String?);
    }
    final body = (res.body.isEmpty ? [] : jsonDecode(res.body)) as List<dynamic>;
    return _MockListResult(
      body
          .map((e) => _MockStorageObject(e as Map<String, dynamic>))
          .toList(),
      null,
    );
  }
}

class _MockStorageObject implements SupabaseStorageObject {
  _MockStorageObject(this._raw);
  final Map<String, dynamic> _raw;

  @override
  String get key => _raw['name'] as String;

  @override
  int get size {
    final meta = _raw['metadata'] as Map?;
    final s = meta?['size'];
    return s is num ? s.toInt() : 0;
  }

  @override
  String? get lastModifiedAt => _raw['updated_at'] as String?;
}

class _MockListResult implements SupabaseListResult {
  @override
  final List<SupabaseStorageObject>? data;
  @override
  final Object? error;
  const _MockListResult(this.data, this.error);
}

class _MockSignedUrlResult implements SupabaseSignedUrlResult {
  @override
  final String? signedUrl;
  @override
  final Object? error;
  const _MockSignedUrlResult(this.signedUrl, this.error);
}

class _MockSignedUrlListResult implements SupabaseSignedUrlListResult {
  @override
  final List<SupabaseSignedUrlResult>? data;
  @override
  final Object? error;
  const _MockSignedUrlListResult(this.data, this.error);
}

class _MockUploadResult implements SupabaseUploadResult {
  @override
  final Object? data;
  @override
  final Object? error;
  const _MockUploadResult(this.data, this.error);
}

class _MockRemoveResult implements SupabaseRemoveResult {
  @override
  final Object? data;
  @override
  final Object? error;
  @override
  final String? message;
  const _MockRemoveResult(this.data, this.message) : error = null;
}

class _MockExistsResult implements SupabaseExistsResult {
  @override
  final bool? data;
  @override
  final Object? error;
  @override
  final String? message;
  const _MockExistsResult(this.data, this.error) : message = null;
}

class _MockDownloadResult implements SupabaseDownloadResult {
  @override
  final List<int>? data;
  @override
  final Object? error;
  @override
  final String? message;
  const _MockDownloadResult(this.data, this.error) : message = null;
}

class _StorageClient implements SupabaseStorageClientLike {
  final String _baseUrl;
  final Map<String, String> _headers;
  _StorageClient(this._baseUrl, this._headers);

  @override
  SupabaseStorageBucketLike from(String bucket) =>
      _StorageBucket(_baseUrl, bucket, _headers);
}

/// [SupabaseClientLike] implementation backed by the Supabase REST API.
class SupabaseHttpClient implements SupabaseClientLike {
  final String _baseUrl;
  final Map<String, String> _headers;

  SupabaseHttpClient(String supabaseUrl, String key)
      : _baseUrl = supabaseUrl,
        _headers = {
          'apikey': key,
          'Authorization': 'Bearer $key',
        };

  @override
  SupabaseQueryBuilderLike from(String table) =>
      _QueryBuilder(_baseUrl, table, _headers);

  @override
  SupabaseStorageClientLike get storage =>
      _StorageClient(_baseUrl, _headers);

  @override
  Future<SupabaseRpcResponse> rpc(
    String functionName, {
    Map<String, dynamic>? params,
  }) async {
    final uri = Uri.parse('$_baseUrl/rest/v1/rpc/$functionName');
    final res = await http.post(
      uri,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: params == null ? null : jsonEncode(params),
    );
    if (res.statusCode >= 400) {
      return _RpcResponse(null, jsonDecode(res.body));
    }
    final body = res.body.isEmpty ? null : jsonDecode(res.body);
    return _RpcResponse(body, null);
  }
}

class _RpcResponse implements SupabaseRpcResponse {
  @override
  final Object? data;
  @override
  final Object? error;
  const _RpcResponse(this.data, this.error);
}

/// Default factory: builds a [SupabaseHttpClient] from credentials.
SupabaseClientLike createSupabaseHttpClient(String url, String key) =>
    SupabaseHttpClient(url, key);
