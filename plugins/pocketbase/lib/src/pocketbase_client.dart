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
  PocketBaseClient._(this._baseUrl, this._token, this._http);

  /// Build a client (unauthenticated). Call [adminCredentials] and
  /// [authenticate] before use, or rely on lazy auth.
  factory PocketBaseClient(String baseUrl, {http.Client? httpClient}) =>
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

  /// Authenticate as admin email / admin password. Idempotent — calling
  /// twice refreshes the token.
  Future<PocketBaseClient> authenticate(
    String adminEmail,
    String password,
  ) async {
    final res = await _http.post(
      Uri.parse('$_baseUrl/api/collections/_superusers/auth-with-password'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'identity': adminEmail, 'password': password}),
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
    req.files.add(
      http.MultipartFile.fromBytes(fieldName, bytes, filename: filename),
    );
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
  String fileUrl(
    String collection,
    String recordId,
    String filename, [
    String? token,
  ]) {
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

  /// Detailed health check returning the full JSON response.
  Future<Map<String, dynamic>> healthDetailed() async {
    final res = await _http.get(Uri.parse('$_baseUrl/api/health'));
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'health check failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ----- Backups -----

  /// List available backups.
  Future<List<PocketBaseBackup>> listBackups() async {
    final res = await _get(Uri.parse('$_baseUrl/api/backups'));
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'listBackups failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    final body = jsonDecode(res.body);
    final items = body is List ? body : <dynamic>[];
    return items
        .map((j) => PocketBaseBackup.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Create a new backup. Optionally provide a [name].
  Future<void> createBackup({String? name}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    final res = await _post(
      Uri.parse('$_baseUrl/api/backups'),
      body: body.isEmpty ? null : body,
    );
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw PocketBaseException(
        'createBackup failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  /// Delete a backup by key.
  Future<void> deleteBackup(String key) async {
    final res = await _delete(Uri.parse('$_baseUrl/api/backups/$key'));
    if (res.statusCode != 204) {
      throw PocketBaseException(
        'deleteBackup($key) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  /// Restore a backup by key (restarts PB).
  Future<void> restoreBackup(String key) async {
    final res = await _post(Uri.parse('$_baseUrl/api/backups/$key/restore'));
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw PocketBaseException(
        'restoreBackup($key) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  /// Get the download URL for a backup file.
  String backupDownloadUrl(String key, String token) {
    return '$_baseUrl/api/backups/$key?token=$token';
  }

  // ----- Admins (superusers collection in PB 0.40+) -----

  /// List admin accounts via the _superusers collection.
  Future<List<Map<String, dynamic>>> listAdmins() async {
    final res = await _get(
      Uri.parse('$_baseUrl/api/collections/_superusers/records?perPage=100'),
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'listAdmins failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['items'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  /// Create a new admin account via the _superusers collection.
  Future<Map<String, dynamic>> createAdmin({
    required String email,
    required String password,
    required String passwordConfirm,
  }) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (_token.isNotEmpty) headers['authorization'] = _token;
    final res = await _http.post(
      Uri.parse('$_baseUrl/api/collections/_superusers/records'),
      headers: headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        'passwordConfirm': passwordConfirm,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw PocketBaseException(
        'createAdmin failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Update an admin account by ID.
  Future<Map<String, dynamic>> updateAdmin(
    String id,
    Map<String, dynamic> data,
  ) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (_token.isNotEmpty) headers['authorization'] = _token;
    final res = await _http.patch(
      Uri.parse('$_baseUrl/api/collections/_superusers/records/$id'),
      headers: headers,
      body: jsonEncode(data),
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'updateAdmin($id) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Delete an admin account by ID.
  Future<void> deleteAdmin(String id) async {
    final headers = <String, String>{};
    if (_token.isNotEmpty) headers['authorization'] = _token;
    final res = await _http.delete(
      Uri.parse('$_baseUrl/api/collections/_superusers/records/$id'),
      headers: headers,
    );
    if (res.statusCode != 204) {
      throw PocketBaseException(
        'deleteAdmin($id) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  // ----- Collection export/import -----

  /// Export all records from a collection as JSON.
  Future<List<Map<String, dynamic>>> exportCollection(String collection) async {
    // PB 0.22.x has no export-records endpoint; fetch all via listRecords.
    final result = await listRecords<Map<String, dynamic>>(
      collection,
      (j) => Map<String, dynamic>.from(j),
      perPage: 500,
    );
    return result.items;
  }

  /// Import records into a collection from a JSON list.
  Future<void> importCollection(
    String collection,
    List<Map<String, dynamic>> records,
  ) async {
    // PB 0.22.x has no import-records endpoint; create records individually.
    for (final record in records) {
      final body = Map<String, dynamic>.from(record)
        ..remove('id')
        ..remove('collectionId')
        ..remove('collectionName')
        ..remove('created')
        ..remove('updated');
      await createRecord<Map<String, dynamic>>(collection, body, (j) => j);
    }
  }

  // ----- Raw request (for query command) -----

  /// Execute an arbitrary HTTP request against the PB API.
  Future<http.Response> rawRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    await _ensureAuth();
    final uri = Uri.parse('$_baseUrl$path');
    switch (method.toUpperCase()) {
      case 'GET':
        return _get(uri);
      case 'POST':
        return _post(uri, body: body);
      case 'PATCH':
        return _patch(uri, body: body);
      case 'DELETE':
        return _delete(uri);
      default:
        throw PocketBaseException('Unsupported method: $method');
    }
  }

  /// Download a file by URL to bytes (unauthenticated).
  Future<List<int>> downloadFileUnauth(String url) async {
    final res = await _http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'downloadFile($url) failed: HTTP ${res.statusCode}',
      );
    }
    return res.bodyBytes;
  }

  // ----- Logs -----

  /// List logs with optional filter and pagination.
  Future<Map<String, dynamic>> listLogs({
    String? filter,
    String? sort,
    int page = 1,
    int perPage = 30,
  }) async {
    final qp = <String, String>{
      'page': page.toString(),
      'perPage': perPage.toString(),
    };
    if (filter != null && filter.isNotEmpty) qp['filter'] = filter;
    if (sort != null && sort.isNotEmpty) qp['sort'] = sort;
    final uri = Uri.parse('$_baseUrl/api/logs').replace(queryParameters: qp);
    final res = await _get(uri);
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'listLogs failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Get a single log by ID.
  Future<Map<String, dynamic>> getLog(String id) async {
    final res = await _get(Uri.parse('$_baseUrl/api/logs/$id'));
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'getLog($id) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Get log statistics.
  Future<List<Map<String, dynamic>>> getLogStats({String? filter}) async {
    final qp = <String, String>{};
    if (filter != null && filter.isNotEmpty) qp['filter'] = filter;
    final uri = Uri.parse('$_baseUrl/api/logs/stats')
        .replace(queryParameters: qp);
    final res = await _get(uri);
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'getLogStats failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    final body = jsonDecode(res.body);
    return body is List ? body.cast<Map<String, dynamic>>() : [];
  }

  /// Truncate all logs.
  Future<void> truncateLogs() async {
    final res = await _delete(Uri.parse('$_baseUrl/api/logs'));
    if (res.statusCode != 204) {
      throw PocketBaseException(
        'truncateLogs failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  // ----- Collections -----

  /// List collections.
  Future<List<Map<String, dynamic>>> listCollections() async {
    final res = await _get(Uri.parse('$_baseUrl/api/collections'));
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'listCollections failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['items'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  /// Get a collection by name or ID.
  Future<Map<String, dynamic>> getCollection(String nameOrId) async {
    final res = await _get(Uri.parse('$_baseUrl/api/collections/$nameOrId'));
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'getCollection($nameOrId) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Create a collection.
  Future<Map<String, dynamic>> createCollection(
    Map<String, dynamic> body,
  ) async {
    final res = await _post(Uri.parse('$_baseUrl/api/collections'), body: body);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw PocketBaseException(
        'createCollection failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Update a collection.
  Future<Map<String, dynamic>> updateCollection(
    String nameOrId,
    Map<String, dynamic> body,
  ) async {
    final res = await _patch(
      Uri.parse('$_baseUrl/api/collections/$nameOrId'),
      body: body,
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'updateCollection($nameOrId) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Delete a collection.
  Future<void> deleteCollection(String nameOrId) async {
    final res = await _delete(Uri.parse('$_baseUrl/api/collections/$nameOrId'));
    if (res.statusCode != 204) {
      throw PocketBaseException(
        'deleteCollection($nameOrId) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  /// Truncate a collection (delete all records).
  Future<void> truncateCollection(String nameOrId) async {
    final res = await _delete(
      Uri.parse('$_baseUrl/api/collections/$nameOrId/truncate'),
    );
    if (res.statusCode != 204) {
      throw PocketBaseException(
        'truncateCollection($nameOrId) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  /// Import collections configuration.
  Future<void> importCollections(
    List<Map<String, dynamic>> collections, {
    bool deleteMissing = false,
  }) async {
    await _ensureAuth();
    final res = await _http.put(
      Uri.parse('$_baseUrl/api/collections/import'),
      headers: {..._authHeaders, 'content-type': 'application/json'},
      body: jsonEncode({
        'collections': collections,
        'deleteMissing': deleteMissing,
      }),
    );
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw PocketBaseException(
        'importCollections failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  // ----- Backup upload -----

  /// Upload a backup zip file.
  Future<void> uploadBackup(List<int> bytes, {String? name}) async {
    await _ensureAuth();
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/backups/upload'),
    );
    req.headers['authorization'] = _token;
    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: name ?? 'backup.zip',
      ),
    );
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw PocketBaseException(
        'uploadBackup failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  // ----- Batch -----

  /// Execute multiple record operations in a single transaction.
  Future<List<Map<String, dynamic>>> batch(
    List<Map<String, dynamic>> requests,
  ) async {
    await _ensureAuth();
    final res = await _http.post(
      Uri.parse('$_baseUrl/api/batch'),
      headers: _authHeaders,
      body: jsonEncode({'requests': requests}),
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'batch failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  // ----- Settings -----

  /// List all application settings.
  Future<Map<String, dynamic>> listSettings() async {
    await _ensureAuth();
    final res = await _http.get(
      Uri.parse('$_baseUrl/api/settings'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'listSettings failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Update application settings.
  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> body) async {
    await _ensureAuth();
    final res = await _http.patch(
      Uri.parse('$_baseUrl/api/settings'),
      headers: {..._authHeaders, 'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'updateSettings failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Test S3 storage connection.
  Future<void> testS3(String filesystem) async {
    await _ensureAuth();
    final res = await _http.post(
      Uri.parse('$_baseUrl/api/settings/test/s3'),
      headers: {..._authHeaders, 'content-type': 'application/json'},
      body: jsonEncode({'filesystem': filesystem}),
    );
    if (res.statusCode != 204) {
      throw PocketBaseException(
        'testS3 failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  /// Send a test email.
  Future<void> testEmail({
    required String email,
    required String template,
    String? collection,
  }) async {
    await _ensureAuth();
    final body = <String, dynamic>{'email': email, 'template': template};
    if (collection != null) body['collection'] = collection;
    final res = await _http.post(
      Uri.parse('$_baseUrl/api/settings/test/email'),
      headers: {..._authHeaders, 'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 204) {
      throw PocketBaseException(
        'testEmail failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  // ----- SQL -----

  /// Execute a raw SQL query.
  Future<Map<String, dynamic>> runSql(String query) async {
    await _ensureAuth();
    final res = await _http.post(
      Uri.parse('$_baseUrl/api/sql'),
      headers: {..._authHeaders, 'content-type': 'application/json'},
      body: jsonEncode({'query': query}),
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'runSql failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ----- Crons -----

  /// List all registered cron jobs.
  Future<List<Map<String, dynamic>>> listCrons() async {
    await _ensureAuth();
    final res = await _http.get(
      Uri.parse('$_baseUrl/api/crons'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'listCrons failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  /// Run a cron job by ID.
  Future<void> runCron(String jobId) async {
    await _ensureAuth();
    final res = await _http.post(
      Uri.parse('$_baseUrl/api/crons/$jobId'),
      headers: _authHeaders,
    );
    if (res.statusCode != 204) {
      throw PocketBaseException(
        'runCron($jobId) failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
  }

  // ----- Collections meta -----

  /// Get collection scaffolds (default field templates).
  Future<Map<String, dynamic>> getCollectionScaffolds() async {
    await _ensureAuth();
    final res = await _http.get(
      Uri.parse('$_baseUrl/api/collections/meta/scaffolds'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'getCollectionScaffolds failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// List all configurable OAuth2 providers.
  Future<List<Map<String, dynamic>>> listOAuth2Providers() async {
    await _ensureAuth();
    final res = await _http.get(
      Uri.parse('$_baseUrl/api/collections/meta/oauth2-providers'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'listOAuth2Providers failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  /// Dry-run a view query and return sample records/fields.
  Future<Map<String, dynamic>> dryRunViewQuery(String query) async {
    await _ensureAuth();
    final res = await _http.post(
      Uri.parse('$_baseUrl/api/collections/meta/dry-run-view'),
      headers: {..._authHeaders, 'content-type': 'application/json'},
      body: jsonEncode({'query': query}),
    );
    if (res.statusCode != 200) {
      throw PocketBaseException(
        'dryRunViewQuery failed: HTTP ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
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

/// A PocketBase backup entry.
class PocketBaseBackup {
  const PocketBaseBackup({
    required this.key,
    required this.modified,
    required this.size,
  });

  factory PocketBaseBackup.fromJson(Map<String, dynamic> j) => PocketBaseBackup(
    key: j['key'] as String? ?? '',
    modified: j['modified'] as String? ?? '',
    size: (j['size'] as num?)?.toInt() ?? 0,
  );

  final String key;
  final String modified;
  final int size;

  String get sizeFormatted {
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (size >= 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '$size B';
  }
}
