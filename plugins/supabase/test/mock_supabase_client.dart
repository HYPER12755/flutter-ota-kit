/// Faithful mock of the Supabase client surface, mirroring hot-updater's
/// `vi.mock("@supabase/supabase-js")` test seam.
///
/// The mock keeps an in-memory set of `bundles` / `bundle_patches` rows and
/// implements the PostgREST query-builder + RPC contract used by the database
/// plugin, plus a configurable storage bucket used by the storage plugin.
library;

import 'package:flutter_patcher_core/flutter_patcher_core.dart';
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart';

import 'package:flutter_patcher_supabase/src/supabase_bundle_mapper.dart';
import 'package:flutter_patcher_supabase/src/supabase_client_adapter.dart';
import 'package:flutter_patcher_supabase/src/types.dart';

// ---------------------------------------------------------------------------
// In-memory row store
// ---------------------------------------------------------------------------

class Store {
  final Map<String, Map<String, dynamic>> bundleRows = {};
  final Map<String, Map<String, dynamic>> bundlePatchRows = {};
}

// ---------------------------------------------------------------------------
// Query builder mock
// ---------------------------------------------------------------------------

sealed class _Filter {
  const _Filter();
}

class _EqFilter extends _Filter {
  final String column;
  final Object? value;
  _EqFilter(this.column, this.value);
}

class _CompareFilter extends _Filter {
  final String type; // gt | gte | lt | lte
  final String column;
  final Object? value;
  _CompareFilter(this.type, this.column, this.value);
}

class _InFilter extends _Filter {
  final String column;
  final List<Object?> values;
  _InFilter(this.column, this.values);
}

class _IsFilter extends _Filter {
  final String column;
  final Object? value;
  _IsFilter(this.column, this.value);
}

class _NotFilter extends _Filter {
  final String column;
  final String operator;
  final Object? value;
  _NotFilter(this.column, this.operator, this.value);
}

int _compareValues(Object? left, Object? right) {
  if (left is String && right is String) return left.compareTo(right);
  if (left is num && right is num) return left.compareTo(right);
  if (left is bool && right is bool) {
    return (left ? 1 : 0).compareTo(right ? 1 : 0);
  }
  return left.toString().compareTo(right.toString());
}

class _MockFilterBuilder implements SupabaseFilterBuilderLike {
  _MockFilterBuilder(
    this._store,
    this._table,
    this._mode, {
    this.head = false,
  });

  final Store _store;
  final String _table;
  final String _mode;
  final bool head;
  final bool count = false;

  final List<_Filter> _filters = [];
  bool ascending = true;
  int? limitValue;
  int? rangeStart;
  int? rangeEnd;
  bool singleRow = false;

  @override
  SupabaseFilterBuilderLike eq(String column, Object? value) {
    _filters.add(_EqFilter(column, value));
    return this;
  }

  @override
  SupabaseFilterBuilderLike gt(String column, Object? value) {
    _filters.add(_CompareFilter('gt', column, value));
    return this;
  }

  @override
  SupabaseFilterBuilderLike gte(String column, Object? value) {
    _filters.add(_CompareFilter('gte', column, value));
    return this;
  }

  @override
  SupabaseFilterBuilderLike lt(String column, Object? value) {
    _filters.add(_CompareFilter('lt', column, value));
    return this;
  }

  @override
  SupabaseFilterBuilderLike lte(String column, Object? value) {
    _filters.add(_CompareFilter('lte', column, value));
    return this;
  }

  @override
  SupabaseFilterBuilderLike in_(String column, List<Object?> values) {
    _filters.add(_InFilter(column, values));
    return this;
  }

  @override
  SupabaseFilterBuilderLike isFilter(String column, Object? value) {
    _filters.add(_IsFilter(column, value));
    return this;
  }

  @override
  SupabaseFilterBuilderLike not(String column, String operator, Object? value) {
    _filters.add(_NotFilter(column, operator, value));
    return this;
  }

  @override
  SupabaseFilterBuilderLike order(String column, {bool? ascending}) {
    this.ascending = ascending ?? true;
    return this;
  }

  @override
  SupabaseFilterBuilderLike limit(int value) {
    limitValue = value;
    return this;
  }

  @override
  SupabaseFilterBuilderLike range(int from, int to) {
    rangeStart = from;
    rangeEnd = to;
    return this;
  }

  @override
  SupabaseFilterBuilderLike single() {
    singleRow = true;
    return this;
  }

  List<Map<String, dynamic>> _rowsForTable() =>
      _table == 'bundles' ? _store.bundleRows.values.toList()
      : _store.bundlePatchRows.values.toList();

  List<Map<String, dynamic>> _getFilteredRows() {
    var rows = _rowsForTable();
    for (final filter in _filters) {
      rows = rows.where((row) {
        return switch (filter) {
          _EqFilter(:final column, :final value) => row[column] == value,
          _CompareFilter(:final type, :final column, :final value) =>
            switch (type) {
              'gt' => _compareValues(row[column], value) > 0,
              'gte' => _compareValues(row[column], value) >= 0,
              'lt' => _compareValues(row[column], value) < 0,
              'lte' => _compareValues(row[column], value) <= 0,
              _ => false,
            },
          _InFilter(:final column, :final values) =>
            values.contains(row[column]),
          _IsFilter(:final column, :final value) => row[column] == value,
          _NotFilter(:final column, :final operator, :final value) =>
            operator == 'is' ? row[column] != value : false,
        };
      }).toList();
    }
    return rows;
  }

  @override
  Future<SupabaseResponseLike> execute() async {
    if (_mode == 'delete') {
      final filtered = _getFilteredRows();
      for (final row in filtered) {
        if (_table == 'bundles') {
          _store.bundleRows.remove(row['id']);
        } else {
          _store.bundlePatchRows.remove(row['id']);
        }
      }
      return _MockResponse(data: null, error: null);
    }

    var filtered = _getFilteredRows();
    filtered = filtered.toList()
      ..sort((a, b) =>
          ascending ? a['id'].compareTo(b['id']) : b['id'].compareTo(a['id']));
    final total = filtered.length;

    if (singleRow) {
      final data = filtered.isEmpty ? null : filtered.first;
      return _MockResponse(
        data: data,
        error: data == null ? {'message': 'Row not found'} : null,
      );
    }

    if (head || count) {
      return _MockResponse(data: null, error: null, count: total);
    }

    if (rangeStart != null && rangeEnd != null) {
      filtered = filtered.sublist(
        rangeStart!,
        (rangeEnd! + 1).clamp(0, filtered.length),
      );
    } else if (limitValue != null && limitValue! > 0) {
      filtered = filtered.sublist(0, limitValue!.clamp(0, filtered.length));
    }

    return _MockResponse(data: filtered, error: null, count: total);
  }
}

// ---------------------------------------------------------------------------
// Storage bucket mock
// ---------------------------------------------------------------------------

class _ExistsResult implements SupabaseExistsResult {
  _ExistsResult({this.data, this.error});
  @override
  final bool? data;
  @override
  final Object? error;
  @override
  final String? message = null;
}

class _SignedUrlResult implements SupabaseSignedUrlResult {
  _SignedUrlResult({this.signedUrl, this.error});
  @override
  final String? signedUrl;
  @override
  final Object? error;
}

class _SignedUrlListResult implements SupabaseSignedUrlListResult {
  _SignedUrlListResult({this.data, this.error});
  @override
  final List<SupabaseSignedUrlResult>? data;
  @override
  final Object? error;
}

class _UploadResult implements SupabaseUploadResult {
  _UploadResult({this.data, this.error});
  @override
  final Object? data;
  @override
  final Object? error;
}

class _RemoveResult implements SupabaseRemoveResult {
  _RemoveResult({this.data, this.error, this.message});
  @override
  final Object? data;
  @override
  final Object? error;
  @override
  final String? message;
}

class _DownloadResult implements SupabaseDownloadResult {
  _DownloadResult({this.data, this.error, this.message});
  @override
  final List<int>? data;
  @override
  final Object? error;
  @override
  final String? message;
}

class _ListResult implements SupabaseListResult {
  _ListResult({this.data, this.error});
  @override
  final List<SupabaseStorageObject>? data;
  @override
  final Object? error;
}

/// Configurable in-memory storage bucket.
class FakeStorageBucket implements SupabaseStorageBucketLike {
  FakeStorageBucket({
    this.existsData,
    this.existsError,
    this.existsThrows,
    this.signedUrlData,
    this.signedUrlError,
    this.uploadData,
    this.uploadError,
    this.removeError,
    this.removeMessage,
    this.downloadData,
    this.downloadError,
    this.downloadMessage,
    this.listData,
    this.listError,
    this.createSignedUrlBase = 'https://example.supabase.co',
  });

  bool? existsData;
  Object? existsError;
  Object? existsThrows;
  String? signedUrlData;
  Object? signedUrlError;
  Object? uploadData;
  Object? uploadError;
  Object? removeError;
  String? removeMessage;
  List<int>? downloadData;
  Object? downloadError;
  String? downloadMessage;
  List<SupabaseStorageObject>? listData;
  Object? listError;
  final String createSignedUrlBase;

  final List<String> existsCalls = [];
  final List<String> createSignedUrlCalls = [];
  final List<List<String>> createSignedUrlsCalls = [];
  final List<String> uploadCalls = [];
  final List<List<String>> removeCalls = [];
  final List<String> downloadCalls = [];
  final List<String> listCalls = [];

  @override
  Future<SupabaseExistsResult> exists(String path) {
    existsCalls.add(path);
    if (existsThrows != null) {
      return Future.error(existsThrows!);
    }
    return Future.value(
      _ExistsResult(data: existsData, error: existsError),
    );
  }

  @override
  Future<SupabaseSignedUrlResult> createSignedUrl(String path, int expiresIn) {
    createSignedUrlCalls.add(path);
    return Future.value(
      _SignedUrlResult(
        signedUrl: signedUrlData ?? '$createSignedUrlBase/signed-url',
        error: signedUrlError,
      ),
    );
  }

  @override
  Future<SupabaseSignedUrlListResult> createSignedUrls(
    List<String> paths,
    int expiresIn,
  ) {
    createSignedUrlsCalls.add(List.of(paths));
    return Future.value(
      _SignedUrlListResult(
        data: paths
            .map((p) => _SignedUrlResult(
                  signedUrl: '$createSignedUrlBase/$expiresIn/$p',
                  error: signedUrlError,
                ))
            .toList(),
        error: signedUrlError,
      ),
    );
  }

  @override
  Future<SupabaseUploadResult> upload(
    String path,
    List<int> fileBytes, {
    String? contentType,
    String? cacheControl,
  }) {
    uploadCalls.add(path);
    return Future.value(
      _UploadResult(
        data: uploadData ?? {'fullPath': path},
        error: uploadError,
      ),
    );
  }

  @override
  Future<SupabaseRemoveResult> remove(List<String> paths) {
    removeCalls.add(List.of(paths));
    return Future.value(
      _RemoveResult(data: [], error: removeError, message: removeMessage),
    );
  }

  @override
  Future<SupabaseDownloadResult> download(String path) {
    downloadCalls.add(path);
    return Future.value(
      _DownloadResult(
        data: downloadData,
        error: downloadError,
        message: downloadMessage,
      ),
    );
  }

  @override
  Future<SupabaseListResult> list([String? prefix]) {
    listCalls.add(prefix ?? '');
    return Future.value(_ListResult(data: listData, error: listError));
  }
}

// ---------------------------------------------------------------------------
// Top-level mock client
// ---------------------------------------------------------------------------

class _MockStorageClient implements SupabaseStorageClientLike {
  _MockStorageClient(this.bucket);
  final SupabaseStorageBucketLike bucket;

  @override
  SupabaseStorageBucketLike from(String bucketName) => bucket;
}

class _MockQueryBuilder implements SupabaseQueryBuilderLike {
  _MockQueryBuilder(this._store, this._table);
  final Store _store;
  final String _table;

  @override
  SupabaseFilterBuilderLike select(
    String columns, {
    bool? count,
    bool? head,
  }) =>
      _MockFilterBuilder(_store, _table, 'select', head: head ?? false);

  @override
  SupabaseFilterBuilderLike delete() =>
      _MockFilterBuilder(_store, _table, 'delete');

  @override
  Future<dynamic> upsert(dynamic values, {String? onConflict}) async {
    final list = values is List ? values : [values];
    for (final value in list) {
      final Map<String, dynamic> map;
      if (value is SupabaseBundleRow) {
        map = value.toJson();
      } else if (value is SupabaseBundlePatchRow) {
        map = value.toJson();
      } else {
        map = Map<String, dynamic>.from(value as Map);
      }
      if (_table == 'bundles') {
        _store.bundleRows[map['id'] as String] = map;
      } else {
        _store.bundlePatchRows[map['id'] as String] = map;
      }
    }
    return _MockResponse(data: null, error: null);
  }
}

class _MockResponse implements SupabaseResponseLike {
  _MockResponse({this.data, this.error, this.count});
  @override
  final Object? data;
  @override
  final Object? error;
  @override
  final int? count;
}

class _MockRpcResponse implements SupabaseRpcResponse {
  _MockRpcResponse({this.data, this.error});
  @override
  final Object? data;
  @override
  final Object? error;
}

/// Build an in-memory mock Supabase client backed by [store] and [bucket].
SupabaseClientLike createMockSupabaseClient({
  required Store store,
  required FakeStorageBucket bucket,
}) {
  final storageClient = _MockStorageClient(bucket);

  Platform platformFrom(String value) =>
      value == 'ios' ? Platform.ios : Platform.android;

  Bundle rowToBundle(Map<String, dynamic> row) => mapRowToBundle(
        SupabaseBundleRow.fromJson(row),
      );

  return _MockClient(store, storageClient, platformFrom, rowToBundle);
}

class _MockClient implements SupabaseClientLike {
  _MockClient(
    this._store,
    this._storage,
    this._platformFrom,
    this._rowToBundle,
  );

  final Store _store;
  final SupabaseStorageClientLike _storage;
  final Platform Function(String) _platformFrom;
  final Bundle Function(Map<String, dynamic>) _rowToBundle;

  @override
  SupabaseQueryBuilderLike from(String table) =>
      _MockQueryBuilder(_store, table);

  @override
  SupabaseStorageClientLike get storage => _storage;

  @override
  Future<SupabaseRpcResponse> rpc(
    String functionName, {
    Map<String, dynamic>? params,
  }) async {
    if (functionName == 'get_channels') {
      final channels = _store.bundleRows.values
          .map((r) => r['channel'] as String)
          .toSet()
          .map((c) => {'channel': c})
          .toList();
      return _MockRpcResponse(data: channels, error: null);
    }

    if (functionName == 'get_target_app_version_list') {
      final platform = params!['app_platform'] as String;
      final minBundleId = params['min_bundle_id'] as String;
      final list = _store.bundleRows.values
          .where((r) =>
              r['platform'] == platform &&
              (r['id'] as String).compareTo(minBundleId) >= 0 &&
              r['target_app_version'] != null)
          .map((r) => r['target_app_version'] as String)
          .toSet()
          .map((v) => {'target_app_version': v})
          .toList();
      return _MockRpcResponse(data: list, error: null);
    }

    if (functionName == 'get_update_info_by_app_version') {
      final platform = params!['app_platform'] as String;
      final appVersion = params['app_version'] as String;
      final bundleId = params['bundle_id'] as String;
      final minBundleId = params['min_bundle_id'] as String;
      final channel = params['target_channel'] as String;
      final targetAppVersionList =
          List<String>.from(params['target_app_version_list'] as List? ?? []);
      final cohort = params['cohort'] as String?;

      final bundles = _store.bundleRows.values
          .where((r) =>
              r['enabled'] == true &&
              r['platform'] == platform &&
              r['channel'] == channel &&
              (r['id'] as String).compareTo(minBundleId) >= 0 &&
              (targetAppVersionList.contains(r['target_app_version'])))
          .map(_rowToBundle)
          .toList();

      final info = await getUpdateInfo(
        bundles,
        AppVersionGetBundlesArgs(
          appVersion: appVersion,
          bundleId: bundleId,
          channel: channel,
          minBundleId: minBundleId,
          platform: _platformFrom(platform),
          cohort: cohort,
        ),
      );
      return _MockRpcResponse(
        data: info == null ? [] : [_toUpdateInfoRow(info)],
        error: null,
      );
    }

    if (functionName == 'get_update_info_by_fingerprint_hash') {
      final platform = params!['app_platform'] as String;
      final bundleId = params['bundle_id'] as String;
      final minBundleId = params['min_bundle_id'] as String;
      final channel = params['target_channel'] as String;
      final fingerprintHash = params['target_fingerprint_hash'] as String;
      final cohort = params['cohort'] as String?;

      final bundles = _store.bundleRows.values
          .where((r) =>
              r['enabled'] == true &&
              r['platform'] == platform &&
              r['channel'] == channel &&
              (r['id'] as String).compareTo(minBundleId) >= 0 &&
              r['fingerprint_hash'] == fingerprintHash)
          .map(_rowToBundle)
          .toList();

      final info = await getUpdateInfo(
        bundles,
        FingerprintGetBundlesArgs(
          fingerprintHash: fingerprintHash,
          bundleId: bundleId,
          channel: channel,
          minBundleId: minBundleId,
          platform: _platformFrom(platform),
          cohort: cohort,
        ),
      );
      return _MockRpcResponse(
        data: info == null ? [] : [_toUpdateInfoRow(info)],
        error: null,
      );
    }

    return _MockRpcResponse(data: null, error: 'Unsupported RPC: $functionName');
  }
}

Map<String, dynamic> _toUpdateInfoRow(UpdateInfo info) => {
      'id': info.id,
      'should_force_update': info.shouldForceUpdate,
      'message': info.message,
      'status': info.status == UpdateStatus.rollback ? 'ROLLBACK' : 'UPDATE',
      'storage_uri': info.storageUri,
      'file_hash': info.fileHash,
    };
