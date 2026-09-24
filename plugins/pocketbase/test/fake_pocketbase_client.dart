/// In-memory [PocketBaseClient] stand-in for plugin tests.
///
/// Unlike a bare stub, this parses the subset of the PocketBase filter DSL that
/// `_PocketBaseDatabase` actually emits (`channel = "x" && platform = "y" &&
/// enabled = true && id >= "..." && target_app_version ?= [..]` etc.) so the
/// database plugin's query building, `getUpdateInfo` branching, pagination and
/// mutations are exercised end-to-end against realistic behavior — the same
/// bar the supabase/postgres/cloudflare/aws plugin tests hit.
library;

import 'package:flutter_ota_kit_pocketbase/flutter_ota_kit_pocketbase.dart';
import 'package:http/http.dart' as http;

/// Backing store: `collection -> (recordId -> row map)` plus a file blob store.
class PbStore {
  final Map<String, Map<String, Map<String, dynamic>>> collections = {};
  final Map<String, List<int>> files = {};

  Map<String, Map<String, dynamic>> records(String collection) =>
      collections.putIfAbsent(collection, () => {});
}

class FakePocketBaseClient implements PocketBaseClient {
  FakePocketBaseClient(this.store);

  final PbStore store;
  bool closed = false;
  String? _email;
  // ignore: unused_field
  String? _password;
  int _autoId = 0;

  @override
  String get authToken => (_email != null) ? 'fake-token' : '';

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

  @override
  Future<bool> health() async => true;

  @override
  Future<bool> recordExists(String collection, String id) async =>
      store.records(collection).containsKey(id);

  @override
  Future<T?> getRecord<T>(
    String collection,
    String id,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final r = store.records(collection)[id];
    return r == null ? null : fromJson(Map<String, dynamic>.from(r));
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
    var rows = store.records(collection).values
        .map((r) => Map<String, dynamic>.from(r))
        .where((r) => _matchesFilter(r, filter))
        .toList();

    if (sort != null && sort.isNotEmpty) {
      final desc = sort.startsWith('-');
      final field = desc ? sort.substring(1) : sort;
      rows.sort((a, b) {
        final av = a[field]?.toString() ?? '';
        final bv = b[field]?.toString() ?? '';
        final cmp = av.compareTo(bv);
        return desc ? -cmp : cmp;
      });
    }

    final total = rows.length;
    final totalPages = total == 0 ? 0 : (total / perPage).ceil();
    final start = (page - 1) * perPage;
    final end = (start + perPage).clamp(0, total);
    final pageRows = start >= total ? <Map<String, dynamic>>[] : rows.sublist(start, end);

    return PocketBaseList<T>(
      items: pageRows.map(fromJson).toList(),
      page: page,
      perPage: perPage,
      totalItems: total,
      totalPages: totalPages,
    );
  }

  /// Parse & evaluate the `&&`-joined filter subset emitted by the plugin.
  bool _matchesFilter(Map<String, dynamic> row, String? filter) {
    if (filter == null || filter.trim().isEmpty) return true;
    for (final clause in filter.split('&&').map((c) => c.trim())) {
      if (!_matchesClause(row, clause)) return false;
    }
    return true;
  }

  bool _matchesClause(Map<String, dynamic> row, String clause) {
    // `field ?= [ "a","b" ]`  (membership)
    final inMatch =
        RegExp(r'^(\w+)\s*\?=\s*\[(.*)\]$').firstMatch(clause);
    if (inMatch != null) {
      final field = inMatch.group(1)!;
      final list = RegExp(r'"((?:[^"\\]|\\.)*)"')
          .allMatches(inMatch.group(2)!)
          .map((m) => _unescape(m.group(1)!))
          .toSet();
      return list.contains(row[field]?.toString());
    }
    // `field != ""`
    final neMatch = RegExp(r'^(\w+)\s*!=\s*"((?:[^"\\]|\\.)*)"$').firstMatch(clause);
    if (neMatch != null) {
      final field = neMatch.group(1)!;
      final val = _unescape(neMatch.group(2)!);
      final cur = row[field];
      return cur != null && cur.toString() != val;
    }
    // `field = true|false`
    final boolMatch = RegExp(r'^(\w+)\s*=\s*(true|false)$').firstMatch(clause);
    if (boolMatch != null) {
      final field = boolMatch.group(1)!;
      final want = boolMatch.group(2) == 'true';
      return (row[field] as bool? ?? false) == want;
    }
    // `field <op> "value"` where op ∈ = > >= < <=
    final cmpMatch =
        RegExp(r'^(\w+)\s*(=|>=|<=|>|<)\s*"((?:[^"\\]|\\.)*)"$').firstMatch(clause);
    if (cmpMatch != null) {
      final field = cmpMatch.group(1)!;
      final op = cmpMatch.group(2)!;
      final val = _unescape(cmpMatch.group(3)!);
      final cur = row[field]?.toString() ?? '';
      final c = cur.compareTo(val);
      switch (op) {
        case '=':
          return cur == val;
        case '>':
          return c > 0;
        case '>=':
          return c >= 0;
        case '<':
          return c < 0;
        case '<=':
          return c <= 0;
      }
    }
    // Unrecognized clause → don't silently pass; fail closed so tests catch it.
    throw StateError('FakePocketBaseClient: unhandled filter clause: "$clause"');
  }

  String _unescape(String s) => s.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');

  @override
  Future<T> createRecord<T>(
    String collection,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final id = (body['id'] as String?) ?? 'rec${_autoId++}';
    if (store.records(collection).containsKey(id)) {
      throw const PocketBaseException('mock: record id already exists');
    }
    final row = Map<String, dynamic>.from(body)..['id'] = id;
    row.putIfAbsent('created', () => id); // creation-ordered by id in tests
    store.records(collection)[id] = row;
    return fromJson(Map<String, dynamic>.from(row));
  }

  @override
  Future<T> updateRecord<T>(
    String collection,
    String id,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final cur = store.records(collection)[id];
    if (cur == null) throw PocketBaseException('not_found: $id');
    cur.addAll(body);
    return fromJson(Map<String, dynamic>.from(cur));
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
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
    final rec = store.records(collection)[recordId];
    if (rec == null) throw PocketBaseException('not_found: $recordId');
    rec[fieldName] = filename;
    store.files['$recordId/$filename'] = List<int>.from(bytes);
    return fromJson(Map<String, dynamic>.from(rec));
  }

  @override
  Future<String> getFileToken(String recordId, String filename) async => 'tok';

  @override
  String fileUrl(
    String collection,
    String recordId,
    String filename, [
    String? token,
  ]) => 'pbfile://$recordId/$filename';

  @override
  Future<List<int>> downloadFile(String url) async {
    final m = RegExp(r'pbfile://([^/]+)/(.+)$').firstMatch(url);
    if (m == null) throw PocketBaseException('bad url: $url');
    final bytes = store.files['${m.group(1)}/${m.group(2)}'];
    if (bytes == null) throw PocketBaseException('not found');
    return bytes;
  }

  @override
  void close() => closed = true;

  // ---- Unused admin/ops surface (not exercised by these tests) ----
  @override
  Future<Map<String, dynamic>> healthDetailed() async => {'code': 200};
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
  }) async => {};
  @override
  Future<Map<String, dynamic>> updateAdmin(
    String id,
    Map<String, dynamic> data,
  ) async => data;
  @override
  Future<void> deleteAdmin(String id) async {}
  @override
  Future<List<Map<String, dynamic>>> exportCollection(String c) async => [];
  @override
  Future<void> importCollection(String c, List<Map<String, dynamic>> r) async {}
  @override
  Future<http.Response> rawRequest(String method, String path,
          {Map<String, dynamic>? body}) async =>
      http.Response('{}', 200);
  @override
  Future<List<int>> downloadFileUnauth(String url) async => [];
  @override
  Future<Map<String, dynamic>> listLogs({
    String? filter,
    String? sort,
    int page = 1,
    int perPage = 30,
  }) async => {'items': []};
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
          Map<String, dynamic> body) async =>
      {};
  @override
  Future<Map<String, dynamic>> updateCollection(
          String nameOrId, Map<String, dynamic> body) async =>
      {};
  @override
  Future<void> deleteCollection(String nameOrId) async {}
  @override
  Future<void> truncateCollection(String nameOrId) async {}
  @override
  Future<void> importCollections(List<Map<String, dynamic>> collections,
      {bool deleteMissing = false}) async {}
  @override
  Future<void> uploadBackup(List<int> bytes, {String? name}) async {}
  @override
  Future<List<Map<String, dynamic>>> batch(
          List<Map<String, dynamic>> requests) async =>
      [];
  @override
  Future<Map<String, dynamic>> listSettings() async => {};
  @override
  Future<Map<String, dynamic>> updateSettings(
          Map<String, dynamic> body) async =>
      {};
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
