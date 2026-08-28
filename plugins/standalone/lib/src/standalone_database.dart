import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show
        AppVersionGetBundlesArgs,
        Bundle,
        FingerprintGetBundlesArgs,
        GetBundlesArgs,
        UpdateInfo,
        UpdateStatus;
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show
        AbstractDatabasePlugin,
        BundleChange,
        BundleChangeOperation,
        DatabaseBundleQueryOptions,
        Paginated,
        PaginationInfo,
        createDatabasePlugin;
import 'package:http/http.dart' as http;
import 'package:http/http.dart';

import 'standalone_config.dart'
    show
        StandaloneRepositoryConfig,
        StandaloneRepositoryRoutes,
        buildPath,
        joinUrl,
        mergeHeaders;

/// Double-curried standalone repository factory.
///
/// Faithful port of hot-updater `plugins/standalone/src/standaloneRepository.ts`.
DatabasePluginLike standaloneRepository(
  StandaloneRepositoryConfig config, [
  Object? hooks,
]) =>
    createDatabasePlugin<StandaloneRepositoryConfig>(
      name: 'standalone-repository',
      factory: (c) => _StandaloneRepository(c),
    )(config);

/// Alias so the curried factory can be used uniformly with other backends.
typedef DatabasePluginLike = dynamic;

class _StandaloneRepository implements AbstractDatabasePlugin {
  _StandaloneRepository(this.config)
      : routes = config.routes ?? const StandaloneRepositoryRoutes();

  final StandaloneRepositoryConfig config;
  final StandaloneRepositoryRoutes routes;

  Client _client() => config.clientFactory?.call() ?? http.Client();

  Map<String, String> _headers([Map<String, String>? extra]) =>
      mergeHeaders(config.commonHeaders, extra);

  Future<dynamic> _decode(Response res) {
    if (res.statusCode >= 400) {
      throw StateError(
        'standalone repository request failed (${res.statusCode}): '
        '${res.body}',
      );
    }
    return Future.value(jsonDecode(res.body));
  }

  @override
  bool get supportsCursorPagination => true;

  @override
  Future<List<String>> getChannels() async {
    final client = _client();
    final res = await client.get(
      Uri.parse(joinUrl(config.baseUrl, routes.channels)),
      headers: _headers({'Cache-Control': 'no-cache'}),
    );
    final decoded = await _decode(res) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>;
    final channels = (data['channels'] as List?)?.cast<String>() ?? const [];
    return channels;
  }

  @override
  Future<Bundle?> getBundleById(String bundleId) async {
    final client = _client();
    final res = await client.get(
      Uri.parse(joinUrl(config.baseUrl, buildPath(routes.retrieve, id: bundleId))),
      headers: _headers({'Accept': 'application/json'}),
    );
    if (res.statusCode == 404) return null;
    final decoded = await _decode(res);
    return Bundle.fromJson(decoded as Map<String, dynamic>);
  }

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) async {
    final client = _client();
    final query = <String, String>{};
    final where = options.where;
    if (where != null) {
      if (where.channel != null) query['channel'] = where.channel!;
      if (where.platform != null) query['platform'] = where.platform!.value;
      if (where.enabled != null) query['enabled'] = '${where.enabled}';
      final id = where.id;
      if (id != null) {
        if (id.eq != null) query['idEq'] = id.eq!;
        if (id.gt != null) query['idGt'] = id.gt!;
        if (id.gte != null) query['idGte'] = id.gte!;
        if (id.lt != null) query['idLt'] = id.lt!;
        if (id.lte != null) query['idLte'] = id.lte!;
        if (id.ins != null) query['idIn'] = id.ins!.join(',');
      }
      if (where.targetAppVersion != null) {
        query['targetAppVersion'] = where.targetAppVersion!;
      }
      if (where.targetAppVersionIn != null) {
        query['targetAppVersionIn'] = where.targetAppVersionIn!.join(',');
      }
      if (where.targetAppVersionNotNull != null) {
        query['targetAppVersionNotNull'] = '${where.targetAppVersionNotNull}';
      }
      if (where.fingerprintHash != null) {
        query['fingerprintHash'] = where.fingerprintHash!;
      }
    }
    query['limit'] = '${options.limit}';
    if (options.page != null) query['page'] = '${options.page}';
    if (options.offset != null) query['offset'] = '${options.offset}';
    if (options.cursor?.after != null) query['after'] = options.cursor!.after!;
    if (options.cursor?.before != null) {
      query['before'] = options.cursor!.before!;
    }

    final uri = Uri.parse(joinUrl(config.baseUrl, routes.list))
        .replace(queryParameters: query);
    final res = await client.get(
      uri,
      headers: _headers({'Cache-Control': 'no-cache'}),
    );
    final decoded = await _decode(res) as Map<String, dynamic>;
    final data = (decoded['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final bundles = data.map(Bundle.fromJson).toList();
    final pagination =
        (decoded['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
    return Paginated(
      data: bundles,
      pagination: PaginationInfo(
        total: pagination['total'] as int? ?? bundles.length,
        hasNextPage: pagination['hasNextPage'] as bool? ?? false,
        hasPreviousPage: pagination['hasPreviousPage'] as bool? ?? false,
        currentPage: pagination['currentPage'] as int? ?? 1,
        totalPages: pagination['totalPages'] as int? ?? 1,
        nextCursor: pagination['nextCursor'] as String?,
        previousCursor: pagination['previousCursor'] as String?,
      ),
    );
  }

  @override
  Future<void> commitBundle({
    required List<BundleChange> changedSets,
  }) async {
    final client = _client();
    for (final change in changedSets) {
      final bundle = change.data;
      switch (change.operation) {
        case BundleChangeOperation.insert:
          final res = await client.post(
            Uri.parse(joinUrl(config.baseUrl, routes.create)),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode([bundle.toJson()]),
          );
          await _decode(res);
        case BundleChangeOperation.update:
          final res = await client.patch(
            Uri.parse(joinUrl(config.baseUrl, buildPath(routes.update, id: bundle.id))),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode(bundle.toJson()),
          );
          await _decode(res);
        case BundleChangeOperation.delete:
          final res = await client.delete(
            Uri.parse(joinUrl(config.baseUrl, buildPath(routes.delete, id: bundle.id))),
          );
          await _decode(res);
      }
    }
  }

  @override
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args) async {
    final client = _client();
    final path = args is AppVersionGetBundlesArgs
        ? _appVersionPath(args)
        : _fingerprintPath(args);
    final res = await client.get(
      Uri.parse(joinUrl(config.baseUrl, path)),
      headers: _headers({'Cache-Control': 'no-cache'}),
    );
    if (res.statusCode == 404) return null;
    final decoded = await _decode(res) as Map<String, dynamic>;
    if (decoded['status'] == 'UP_TO_DATE') return null;
    return UpdateInfo(
      id: decoded['id'] as String,
      shouldForceUpdate: (decoded['shouldForceUpdate'] ?? false) as bool,
      message: decoded['message'] as String?,
      status: UpdateStatus.fromValue(
        decoded['status'] as String? ?? 'update-available',
      ),
      storageUri: decoded['fileUrl'] as String?,
      fileHash: decoded['fileHash'] as String?,
    );
  }

  String _fingerprintPath(GetBundlesArgs args) {
    final fp = args is FingerprintGetBundlesArgs ? args.fingerprintHash : 'unknown';
    final cohort = args.cohort != null ? '/${args.cohort}' : '';
    return '/api/fingerprint/${args.platform.value}/$fp/'
        '${args.channel}/${args.minBundleId}/${args.bundleId}$cohort';
  }

  String _appVersionPath(AppVersionGetBundlesArgs args) {
    final cohort = args.cohort != null ? '/${args.cohort}' : '';
    return '/api/app-version/${args.platform.value}/${args.appVersion}/'
        '${args.channel}/${args.minBundleId}/${args.bundleId}$cohort';
  }

  @override
  Future<void> onUnmount() async {}
}
