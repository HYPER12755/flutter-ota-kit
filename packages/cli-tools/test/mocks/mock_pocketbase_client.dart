/// In-memory mock of [PocketBaseClient] for tests.
///
/// Implements the same surface as the real client but stores everything in
/// Dart maps. Used by the `pocketbase backend` lifecycle test in
/// `backends_test.dart`.
library;

import 'package:flutter_ota_kit_pocketbase/flutter_ota_kit_pocketbase.dart';

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
    final id = (body['id'] as String?) ?? DateTime.now().microsecondsSinceEpoch.toString();
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
  String fileUrl(String collection, String recordId, String filename,
          [String? token]) =>
      'pb://mock/$collection/$recordId/$filename';

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
