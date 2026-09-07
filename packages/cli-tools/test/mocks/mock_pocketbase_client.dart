/// In-memory mock of [PocketBaseClient] for tests.
///
/// Implements the same surface as the real client but stores everything in
/// Dart maps. Used by the `pocketbase backend` lifecycle test in
/// `backends_test.dart`.
library;

import 'package:flutter_ota_kit_pocketbase/flutter_ota_kit_pocketbase.dart';
import 'package:http/http.dart' as http;

class MockPocketBaseClient implements PocketBaseClient {
  MockPocketBaseClient(this.store);

  final PocketBaseStore store;

  bool _closed = false;
  bool get isClosed => _closed;
  String? _email;
  String? _password;

  @override
  void adminCredentials(String email, String password) {
    _email = email;
    _password = password;
  }

  @override
  Future<PocketBaseClient> authenticate(String email, String password) async {
    _email = email;
    _password = password;
    return this;
  }

  void _checkAuth() {
    if (_email == null || _password == null) {
      throw const PocketBaseException('not authenticated');
    }
  }

  @override
  Future<bool> health() async => true;

  @override
  Future<bool> recordExists(String collection, String id) async {
    _checkAuth();
    return store.records(collection).containsKey(id);
  }

  @override
  Future<T?> getRecord<T>(
    String collection,
    String id,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    _checkAuth();
    final r = store.records(collection)[id];
    if (r == null) return null;
    return fromJson(Map<String, dynamic>.from(r));
  }

  @override
  Future<PocketBaseList<T>> listRecords<T>(
    String collection,
    T Function(Map<String, dynamic>) fromJson, {
    String? filter,
    String? sort,
    int page = 1,
    int perPage = 50,
  }) async {
    _checkAuth();
    // Sort the underlying JSON maps BEFORE decoding to typed objects, so the
    // sort field is always available regardless of the decoded bean shape.
    final rawList = store.records(collection).values.toList();
    if (sort != null && sort.isNotEmpty) {
      final desc = sort.startsWith('-');
      final field = desc ? sort.substring(1) : sort;
      rawList.sort((a, b) {
        final av = a[field]?.toString() ?? '';
        final bv = b[field]?.toString() ?? '';
        final cmp = av.compareTo(bv);
        return desc ? -cmp : cmp;
      });
    }
    final all = rawList
        .map((j) => fromJson(Map<String, dynamic>.from(j)))
        .toList();
    final start = (page - 1) * perPage;
    final end = (start + perPage).clamp(0, all.length);
    final items = start >= all.length ? <T>[] : all.sublist(start, end);
    final totalPages = all.isEmpty ? 0 : (all.length / perPage).ceil();
    return PocketBaseList<T>(
      items: items,
      page: page,
      perPage: perPage,
      totalItems: all.length,
      totalPages: totalPages,
    );
  }

  @override
  Future<T> createRecord<T>(
    String collection,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    _checkAuth();
    final id =
        (body['id'] as String?) ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final existing = store.records(collection)[id];
    if (existing != null) {
      // PB returns 409 on duplicate id; the mock simulates the real API by
      // throwing. Callers should use updateRecord() to patch existing rows.
      throw const PocketBaseException('mock: record id already exists');
    }
    store.records(collection)[id] = Map<String, dynamic>.from(body);
    return fromJson(store.records(collection)[id]!);
  }

  @override
  Future<T> updateRecord<T>(
    String collection,
    String id,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    _checkAuth();
    final existing = store.records(collection);
    final current = existing[id];
    if (current == null) {
      throw PocketBaseException('not_found: $id');
    }
    current.addAll(body);
    return fromJson(Map<String, dynamic>.from(current));
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
    _checkAuth();
    store.records(collection).remove(id);
  }

  @override
  Future<T> uploadFile<T>(
    String collection,
    String recordId,
    String fieldName,
    String filename,
    List<int> bytes, {
    Map<String, String>? extraFields,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    _checkAuth();
    final rec = store.records(collection)[recordId];
    if (rec == null) throw PocketBaseException('not_found: $recordId');
    rec[fieldName] = filename;
    store.fileStorage['$recordId/$filename'] = List<int>.from(bytes);
    return fromJson(Map<String, dynamic>.from(rec));
  }

  @override
  Future<String> getFileToken(String recordId, String filename) async => 'mock';

  @override
  String fileUrl(
    String collection,
    String recordId,
    String filename, [
    String? token,
  ]) => 'pb://mock/$collection/$recordId/$filename';

  @override
  Future<List<int>> downloadFile(String url) async {
    final match = RegExp(r'pb://mock/[^/]+/([^/]+)/(.+)$').firstMatch(url);
    if (match == null) throw PocketBaseException('bad url: $url');
    final key = '${match.group(1)}/${match.group(2)}';
    final bytes = store.fileStorage[key];
    if (bytes == null) throw PocketBaseException('not found: $key');
    return bytes;
  }

  @override
  void close() {
    _closed = true;
  }

  @override
  Future<Map<String, dynamic>> healthDetailed() async => {
    'code': 200,
    'message': 'API is healthy.',
    'data': {'canBackup': false},
  };

  @override
  Future<List<PocketBaseBackup>> listBackups() async => [];

  @override
  Future<void> createBackup({String? name}) async {}

  @override
  Future<void> deleteBackup(String key) async {}

  @override
  Future<void> restoreBackup(String key) async {}

  @override
  String backupDownloadUrl(String key, String token) => '';

  @override
  Future<List<Map<String, dynamic>>> listAdmins() async => [];

  @override
  Future<Map<String, dynamic>> createAdmin({
    required String email,
    required String password,
    required String passwordConfirm,
  }) async => {'id': 'mock_admin', 'email': email};

  @override
  Future<Map<String, dynamic>> updateAdmin(
    String id,
    Map<String, dynamic> data,
  ) async => data;

  @override
  Future<void> deleteAdmin(String id) async {}

  @override
  Future<List<Map<String, dynamic>>> exportCollection(String collection) async =>
      [];

  @override
  Future<void> importCollection(
    String collection,
    List<Map<String, dynamic>> records,
  ) async {}

  @override
  Future<http.Response> rawRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async => http.Response('{}', 200);

  @override
  Future<List<int>> downloadFileUnauth(String url) async => [];

  @override
  Future<Map<String, dynamic>> listLogs({
    String? filter, String? sort, int page = 1, int perPage = 30,
  }) async => {'items': [], 'totalItems': 0};

  @override
  Future<Map<String, dynamic>> getLog(String id) async => {};

  @override
  Future<List<Map<String, dynamic>>> getLogStats({String? filter}) async => [];

  @override
  Future<void> truncateLogs() async {}

  @override
  Future<List<Map<String, dynamic>>> listCollections() async => [];

  @override
  Future<Map<String, dynamic>> getCollection(String nameOrId) async => {};

  @override
  Future<Map<String, dynamic>> createCollection(
    Map<String, dynamic> body,
  ) async => body;

  @override
  Future<Map<String, dynamic>> updateCollection(
    String nameOrId,
    Map<String, dynamic> body,
  ) async => body;

  @override
  Future<void> deleteCollection(String nameOrId) async {}

  @override
  Future<void> truncateCollection(String nameOrId) async {}

  @override
  Future<void> importCollections(
    List<Map<String, dynamic>> collections, {
    bool deleteMissing = false,
  }) async {}

  @override
  Future<void> uploadBackup(List<int> bytes, {String? name}) async {}

  @override
  Future<List<Map<String, dynamic>>> batch(
    List<Map<String, dynamic>> requests,
  ) async => [];

  @override
  Future<Map<String, dynamic>> listSettings() async => {};

  @override
  Future<Map<String, dynamic>> updateSettings(
    Map<String, dynamic> body,
  ) async => body;

  @override
  Future<void> testS3(String filesystem) async {}

  @override
  Future<void> testEmail({
    required String email,
    required String template,
    String? collection,
  }) async {}

  @override
  Future<Map<String, dynamic>> runSql(String query) async => {};

  @override
  Future<List<Map<String, dynamic>>> listCrons() async => [];

  @override
  Future<void> runCron(String jobId) async {}

  @override
  Future<Map<String, dynamic>> getCollectionScaffolds() async => {};

  @override
  Future<List<Map<String, dynamic>>> listOAuth2Providers() async => [];

  @override
  Future<Map<String, dynamic>> dryRunViewQuery(String query) async => {};
}

/// In-memory store backing [MockPocketBaseClient].
class PocketBaseStore {
  final Map<String, Map<String, Map<String, dynamic>>> _records = {};
  final Map<String, List<int>> _files = {};

  Map<String, Map<String, dynamic>> records(String collection) =>
      _records.putIfAbsent(collection, () => <String, Map<String, dynamic>>{});

  Map<String, List<int>> get fileStorage => _files;
  Map<String, Map<String, Map<String, dynamic>>> get allRecords => _records;
}
