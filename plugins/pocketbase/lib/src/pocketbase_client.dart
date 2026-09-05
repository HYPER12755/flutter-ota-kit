/// Minimal PocketBase HTTP client (REST API).
///
/// PocketBase is a single-binary Go backend that exposes a REST API at
/// `/api/`. The official `pocketbase` Dart package exists but pulls in
/// `dart:io`/`dart:html` polyfills that conflict with Flutter Web, so we
/// implement just the subset we need on top of `package:http`.
///
/// See: https://pocketbase.io/docs/api-records/
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Factory for creating [PocketBaseClient] instances. Allows tests to inject
/// a fake client without spinning up a real PB server.
typedef PocketBaseClientFactory = PocketBaseClient Function(
  String baseUrl,
  String adminEmail,
  String adminPassword,
);

/// A thin REST client for PocketBase admin operations.
///
/// Authenticates with the admin collection to obtain a long-lived auth token,
/// then exposes typed helpers for CRUD on collections and file storage.
class PocketBaseClient {
  PocketBaseClient._(
    this._baseUrl,
    this._token,
    this._http,
  );

  /// Build a client (unauthenticated). Call [adminCredentials] and
  /// [authenticate] before use, or rely on lazy auth.
  factory PocketBaseClient(
    String baseUrl, {
    http.Client? httpClient,
  }) =>
      PocketBaseClient._(
        _normalizeUrl(baseUrl),
        '',
        httpClient ?? http.Client(),
      );

  final String _baseUrl;
  String _token;
  final http.Client _http;

  static String _normalizeUrl(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  /// Provide admin credentials for lazy authentication.
  void adminCredentials(String email, String password) {
    _adminEmail = email;
    _adminPassword = password;
  }

  /// Authenticate as [adminEmail] / [adminPassword]. Idempotent — calling
  /// twice refreshes the token.
  Future<PocketBaseClient> authenticate(
    String adminEmail,
    String adminPassword,
  ) async {
    final res = await _http.post(
      Uri.parse('$_baseUrl/api/admins/auth-with-password'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'identity': adminEmail, 'password': adminPassword}),
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'PocketBase admin auth failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    _token = body['token'] as String? ?? '';
    if (_token.isEmpty) {
      throw PocketBaseException(
        'PocketBase admin auth returned no token. Is the admins collection '
        'set up? Run `flutter_ota_kit serve` once to install the schema.',
      );
    }
    return this;
  }

  String? _adminEmail;
  String? _adminPassword;
  Future<void>? _authInFlight;

  Map<String, String> get _authHeaders => {
        'content-type': 'application/json',
        'authorization': _token,
      };

  Future<void> _ensureAuth() {
    if (_token.isNotEmpty) return Future.value();
    if (_adminEmail == null || _adminPassword == null) {
      throw PocketBaseException(
        'PocketBase client has no credentials. Call adminCredentials() first.',
      );
    }
    _authInFlight ??= authenticate(_adminEmail!, _adminPassword!);
    return _authInFlight!;
  }

  Future<http.Response> _get(Uri uri) async {
    await _ensureAuth();
    return _http.get(uri, headers: _authHeaders);
  }

  Future<http.Response> _post(Uri uri, {Object? body}) async {
    await _ensureAuth();
    return _http.post(
      uri,
      headers: _authHeaders,
      body: body == null ? null : jsonEncode(body),
    );
  }

  Future<http.Response> _patch(Uri uri, {Object? body}) async {
    await _ensureAuth();
    return _http.patch(
      uri,
      headers: _authHeaders,
      body: body == null ? null : jsonEncode(body),
    );
  }

  Future<http.Response> _delete(Uri uri) async {
    await _ensureAuth();
    return _http.delete(uri, headers: _authHeaders);
  }

  // ----- Records -----

  /// List records from a collection with optional filter, sort, and page.
  Future<PocketBaseList<T>> listRecords<T>(
    String collection,
    T Function(Map<String, dynamic>) fromJson, {
    String? filter,
    String? sort,
    int page = 1,
    int perPage = 50,
  }) async {
    final qp = <String, String>{
      'page': page.toString(),
      'perPage': perPage.toString(),
    };
    if (filter != null && filter.isNotEmpty) qp['filter'] = filter;
    if (sort != null && sort.isNotEmpty) qp['sort'] = sort;
    final uri = Uri.parse('$_baseUrl/api/collections/$collection/records')
        .replace(queryParameters: qp);
    final res = await _get(uri);
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'listRecords($collection) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['items'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(fromJson)
        .toList();
    return PocketBaseList<T>(
      items: items,
      page: (body['page'] as num?)?.toInt() ?? page,
      perPage: (body['perPage'] as num?)?.toInt() ?? perPage,
      totalItems: (body['totalItems'] as num?)?.toInt() ?? items.length,
      totalPages: (body['totalPages'] as num?)?.toInt() ?? 1,
    );
  }

  /// Get a single record by ID.
  Future<T?> getRecord<T>(
    String collection,
    String id,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final res = await _get(
      Uri.parse('$_baseUrl/api/collections/$collection/records/$id'),
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'getRecord($collection/$id) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Create a new record.
  Future<T> createRecord<T>(
    String collection,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final res = await _post(
      Uri.parse('$_baseUrl/api/collections/$collection/records'),
      body: body,
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw PocketBaseException(
        'createRecord($collection) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Update an existing record.
  Future<T> updateRecord<T>(
    String collection,
    String id,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final res = await _patch(
      Uri.parse('$_baseUrl/api/collections/$collection/records/$id'),
      body: body,
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'updateRecord($collection/$id) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Delete a record.
  Future<void> deleteRecord(String collection, String id) async {
    final res = await _delete(
      Uri.parse('$_baseUrl/api/collections/$collection/records/$id'),
    );
    if (res.statusCode != 204) {
      throw PocketBaseException(
        'deleteRecord($collection/$id) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  // ----- Files -----

  /// Upload a file to a record's file field (multipart/form-data).
  Future<T> uploadFile<T>(
    String collection,
    String recordId,
    String fieldName,
    String filename,
    List<int> bytes, {
    Map<String, String>? extraFields,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    await _ensureAuth();
    final req = http.MultipartRequest(
      'PATCH',
      Uri.parse(
        '$_baseUrl/api/collections/$collection/records/$recordId/$fieldName',
      ),
    );
    req.headers['authorization'] = _token;
    if (extraFields != null) req.fields.addAll(extraFields);
    req.files.add(http.MultipartFile.fromBytes(
      fieldName,
      bytes,
      filename: filename,
    ));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'uploadFile($collection/$recordId) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Get a download token for a record's file field.
  Future<String> getFileToken(String recordId, String filename) async {
    final res = await _post(Uri.parse('$_baseUrl/api/files/token'));
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'getFileToken failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['token'] as String? ?? '';
  }

  /// Build a public download URL for a record's file field.
  String fileUrl(String collection, String recordId, String filename,
      [String? token]) {
    final t = token == null ? '' : '?token=$token';
    return '$_baseUrl/api/files/$collection/$recordId/$filename$t';
  }

  /// Download a file by URL (returns bytes).
  Future<List<int>> downloadFile(String url) async {
    final res = await _http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'downloadFile($url) failed: HTTP ${res.statusCode}',
      );
    }
    return res.bodyBytes;
  }

  /// Check if a record exists in a collection.
  Future<bool> recordExists(String collection, String id) async {
    final res = await _get(
      Uri.parse('$_baseUrl/api/collections/$collection/records/$id'),
    );
    return res.statusCode == 200;
  }

  /// Health check (PB exposes /api/health).
  Future<bool> health() async {
    try {
      final res = await _http.get(Uri.parse('$_baseUrl/api/health'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void close() => _http.close();
}

/// Paginated list response from PocketBase.
class PocketBaseList<T> {
  const PocketBaseList({
    required this.items,
    required this.page,
    required this.perPage,
    required this.totalItems,
    required this.totalPages,
  });

  final List<T> items;
  final int page;
  final int perPage;
  final int totalItems;
  final int totalPages;
}

/// Exception thrown by [PocketBaseClient] for any non-2xx response.
class PocketBaseException implements Exception {
  const PocketBaseException(this.message);
  final String message;
  @override
  String toString() => 'PocketBaseException: $message';
}
