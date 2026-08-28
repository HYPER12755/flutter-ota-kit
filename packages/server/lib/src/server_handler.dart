import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show Directory, File;

import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show
        AppUpdateAvailableInfo,
        AppUpToDateInfo,
        AppVersionGetBundlesArgs,
        Bundle,
        FingerprintGetBundlesArgs,
        Platform;
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show
        DatabaseBundleCursor,
        DatabaseBundleIdFilter,
        DatabaseBundleQueryOptions,
        DatabaseBundleQueryWhere,
        NodeStorageProfile,
        PaginationInfo,
        RuntimeStorageProfile,
        StoragePlugin;
import 'package:shelf/shelf.dart' show Handler, Request, Response;

import 'router.dart' show Router;
import 'server_types.dart' show HandlerAPI, HandlerBadRequestError, HandlerRoutes;
import 'version.dart' show hotUpdaterServerVersion;

const String _sdkVersionHeader = 'hot-updater-sdk-version';
const String _explicitNoUpdateMinSdkVersion = '0.31.0';

typedef _RouteHandler = Future<Response> Function(
  Map<String, String> params,
  Request request,
  HandlerAPI api,
);

Response _json(Object? body, int status) => Response(
      status,
      body: body == null ? 'null' : jsonEncode(body),
      headers: {'content-type': 'application/json'});

String _requireParam(Map<String, String> params, String key) {
  final value = params[key];
  if (value == null || value.isEmpty) {
    throw HandlerBadRequestError('Missing route parameter: $key');
  }
  return value;
}

bool _isPlatform(String value) => value == 'ios' || value == 'android';

Platform _requirePlatform(String? value) {
  if (value == null || !_isPlatform(value)) {
    throw HandlerBadRequestError('Invalid platform: $value');
  }
  return Platform.fromValue(value);
}

bool? _parseBool(Request request, String key) {
  final value = request.url.queryParameters[key];
  if (value == null) return null;
  if (value == 'true') return true;
  if (value == 'false') return false;
  throw HandlerBadRequestError(
    "The '$key' query parameter must be 'true' or 'false'.",
  );
}

int _parsePositiveInt(Request request, String key, int def, int max) {
  final value = request.url.queryParameters[key];
  if (value == null) return def;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 1 || parsed > max) {
    throw HandlerBadRequestError(
      "The '$key' query parameter must be a positive integer between 1 and $max.",
    );
  }
  return parsed;
}

bool _supportsExplicitNoUpdate(Request request) {
  final sdk = request.headers[_sdkVersionHeader]?.trim();
  if (sdk == null || sdk.isEmpty) return false;
  return _isGreaterOrEqual(_normalizeSemver(sdk), _explicitNoUpdateMinSdkVersion);
}

List<int>? _normalizeSemver(String v) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(v);
  if (m == null) return null;
  return [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)];
}

bool _isGreaterOrEqual(List<int>? a, String b) {
  final pb = _normalizeSemver(b);
  if (a == null || pb == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != pb[i]) return a[i] > pb[i];
  }
  return true;
}

Object? _serializeUpdateInfo(AppUpdateAvailableInfo? update, Request request) {
  if (update != null) return update.toJson();
  if (_supportsExplicitNoUpdate(request)) {
    return const AppUpToDateInfo().toJson();
  }
  return null;
}

Map<String, Object?> _paginationToJson(PaginationInfo p) => {
      'total': p.total,
      'hasNextPage': p.hasNextPage,
      'hasPreviousPage': p.hasPreviousPage,
      'currentPage': p.currentPage,
      'totalPages': p.totalPages,
      if (p.nextCursor != null) 'nextCursor': p.nextCursor!,
      if (p.previousCursor != null) 'previousCursor': p.previousCursor!,
    };

// --- Route handlers --------------------------------------------------------

Future<Response> _handleVersion(
  Map<String, String> params,
  Request request,
  HandlerAPI api,
) async =>
    _json({'version': hotUpdaterServerVersion}, 200);

Future<Response> _handleFingerprintUpdateWithCohort(
  Map<String, String> params,
  Request request,
  HandlerAPI api,
) async {
  final update = await api.getAppUpdateInfo(
    FingerprintGetBundlesArgs(
      platform: _requirePlatform(params['platform']),
      fingerprintHash: _requireParam(params, 'fingerprintHash'),
      channel: _requireParam(params, 'channel'),
      minBundleId: _requireParam(params, 'minBundleId'),
      bundleId: _requireParam(params, 'bundleId'),
      cohort: params['cohort'],
    ),
  );
  return _json(_serializeUpdateInfo(update, request), 200);
}

Future<Response> _handleAppVersionUpdateWithCohort(
  Map<String, String> params,
  Request request,
  HandlerAPI api,
) async {
  final update = await api.getAppUpdateInfo(
    AppVersionGetBundlesArgs(
      platform: _requirePlatform(params['platform']),
      appVersion: _requireParam(params, 'appVersion'),
      channel: _requireParam(params, 'channel'),
      minBundleId: _requireParam(params, 'minBundleId'),
      bundleId: _requireParam(params, 'bundleId'),
      cohort: params['cohort'],
    ),
  );
  return _json(_serializeUpdateInfo(update, request), 200);
}

Future<Response> _handleGetBundle(
  Map<String, String> params,
  Request request,
  HandlerAPI api,
) async {
  final id = _requireParam(params, 'id');
  final bundle = await api.getBundleById(id);
  if (bundle == null) return _json({'error': 'Bundle not found'}, 404);
  return _json(bundle.toJson(), 200);
}

Future<Response> _handleGetBundles(
  Map<String, String> params,
  Request request,
  HandlerAPI api,
) async {
  final url = request.url;
  final channel = url.queryParameters['channel'];
  final platformStr = url.queryParameters['platform'];
  final limit = _parsePositiveInt(request, 'limit', 50, 100);
  final pageParam = url.queryParameters['page'];
  final offset = url.queryParameters['offset'];
  final after = url.queryParameters['after'];
  final before = url.queryParameters['before'];
  final enabled = _parseBool(request, 'enabled');
  final targetAppVersion = url.queryParameters['targetAppVersion'];
  final targetAppVersionIn = url.queryParametersAll['targetAppVersionIn'];
  final targetAppVersionNotNull = _parseBool(request, 'targetAppVersionNotNull');
  final fingerprintHash = url.queryParameters['fingerprintHash'];
  final idEq = url.queryParameters['idEq'];
  final idGt = url.queryParameters['idGt'];
  final idGte = url.queryParameters['idGte'];
  final idLt = url.queryParameters['idLt'];
  final idLte = url.queryParameters['idLte'];
  final idIn = url.queryParametersAll['idIn'];

  if (offset != null) {
    throw HandlerBadRequestError(
      "The 'offset' query parameter has been removed. Use 'after' or 'before' "
      'cursor pagination instead.',
    );
  }

  final int? page = pageParam == null
      ? 1
      : (int.tryParse(pageParam) != null && int.parse(pageParam) > 0
          ? int.parse(pageParam)
          : null);
  if (page == null) {
    throw HandlerBadRequestError(
      "The 'page' query parameter must be a positive integer.",
    );
  }

  if (platformStr != null && !_isPlatform(platformStr)) {
    throw HandlerBadRequestError(
      'Invalid platform: $platformStr. Expected ios or android.',
    );
  }

  final where = DatabaseBundleQueryWhere(
    channel: channel,
    platform: platformStr != null ? Platform.fromValue(platformStr) : null,
    enabled: enabled,
    id: (idEq != null ||
            idGt != null ||
            idGte != null ||
            idLt != null ||
            idLte != null ||
            (idIn != null && idIn.isNotEmpty))
        ? DatabaseBundleIdFilter(
            eq: idEq,
            gt: idGt,
            gte: idGte,
            lt: idLt,
            lte: idLte,
            ins: idIn,
          )
        : null,
    targetAppVersion: targetAppVersion,
    targetAppVersionIn: targetAppVersionIn,
    targetAppVersionNotNull: targetAppVersionNotNull,
    fingerprintHash: fingerprintHash,
  );

  final result = await api.getBundles(
    DatabaseBundleQueryOptions(
      where: where,
      limit: limit,
      page: page,
      cursor: (after != null || before != null)
          ? DatabaseBundleCursor(after: after, before: before)
          : null,
    ),
  );

  return _json(
    {
      'data': result.data.map((b) => b.toJson()).toList(),
      'pagination': _paginationToJson(result.pagination),
    },
    200,
  );
}

Future<Response> _handleCreateBundles(
  Map<String, String> params,
  Request request,
  HandlerAPI api,
) async {
  final decoded = jsonDecode(await request.readAsString());
  final list = decoded is List ? decoded : [decoded];
  for (final item in list) {
    await api.insertBundle(
      Bundle.fromJson(item as Map<String, dynamic>),
    );
  }
  return _json({'success': true}, 201);
}

Future<Response> _handleUpdateBundle(
  Map<String, String> params,
  Request request,
  HandlerAPI api,
) async {
  final id = _requireParam(params, 'id');
  final decoded = jsonDecode(await request.readAsString());
  final payload = decoded is List ? decoded.first : decoded;
  if (payload is! Map) throw HandlerBadRequestError('Invalid bundle payload');
  final patch = (payload as Map<String, dynamic>);
  if (patch['id'] != null && patch['id'] != id) {
    throw HandlerBadRequestError('Bundle id mismatch');
  }
  patch.remove('id');
  await api.updateBundleById(id, patch);
  return _json({'success': true}, 200);
}

Future<Response> _handleDeleteBundle(
  Map<String, String> params,
  Request request,
  HandlerAPI api,
) async {
  final id = _requireParam(params, 'id');
  await api.deleteBundleById(id);
  return _json({'success': true}, 200);
}

Future<Response> _handleGetChannels(
  Map<String, String> params,
  Request request,
  HandlerAPI api,
) async {
  final channels = await api.getChannels();
  return _json({'data': {'channels': channels}}, 200);
}

/// Create a shelf [Handler] for the Hot Updater API.
///
/// Faithful port of hot-updater `createHandler.ts` (framework-agnostic Web
/// Standard Request/Response → shelf `Request`/`Response`).
Handler createHandler(
  HandlerAPI api, {
  String basePath = '/api',
  HandlerRoutes? routes,
  StoragePlugin? storage,
}) {
  final routeOptions = HandlerRoutes(
    updateCheck: routes?.updateCheck ?? true,
    bundles: routes?.bundles ?? false,
    storage: routes?.storage ?? false,
  );

  if (routeOptions.storage && storage == null) {
    throw ArgumentError(
      'HandlerRoutes.storage is enabled but no storage plugin was provided',
    );
  }

  final router = Router();
  router.add('GET', '/version', 'version');

  if (routeOptions.updateCheck) {
    router.add(
      'GET',
      '/fingerprint/:platform/:fingerprintHash/:channel/:minBundleId/:bundleId',
      'fingerprintUpdateWithCohort',
    );
    router.add(
      'GET',
      '/fingerprint/:platform/:fingerprintHash/:channel/:minBundleId/:bundleId/:cohort',
      'fingerprintUpdateWithCohort',
    );
    router.add(
      'GET',
      '/app-version/:platform/:appVersion/:channel/:minBundleId/:bundleId',
      'appVersionUpdateWithCohort',
    );
    router.add(
      'GET',
      '/app-version/:platform/:appVersion/:channel/:minBundleId/:bundleId/:cohort',
      'appVersionUpdateWithCohort',
    );
  }

  if (routeOptions.bundles) {
    router.add('GET', '/bundles/channels', 'getChannels');
    router.add('GET', '/bundles/:id', 'getBundle');
    router.add('GET', '/bundles', 'getBundles');
    router.add('POST', '/bundles', 'createBundles');
    router.add('PATCH', '/bundles/:id', 'updateBundle');
    router.add('DELETE', '/bundles/:id', 'deleteBundle');
  }

  if (routeOptions.storage && storage != null) {
    router.add('POST', '/upload', 'upload');
    router.add('POST', '/getDownloadUrl', 'getDownloadUrl');
    router.add('DELETE', '/delete', 'delete');
    router.add('POST', '/readText', 'readText');
    router.add('GET', '/list', 'list');
    router.add('GET', '/_file', 'serveFile');
  }

  final handlers = <String, _RouteHandler>{
    'version': _handleVersion,
    'fingerprintUpdateWithCohort': _handleFingerprintUpdateWithCohort,
    'appVersionUpdateWithCohort': _handleAppVersionUpdateWithCohort,
    'getBundle': _handleGetBundle,
    'getBundles': _handleGetBundles,
    'createBundles': _handleCreateBundles,
    'updateBundle': _handleUpdateBundle,
    'deleteBundle': _handleDeleteBundle,
    'getChannels': _handleGetChannels,
  };

  if (routeOptions.storage && storage != null) {
    final node = storage.profiles.node!;
    final runtime = storage.profiles.runtime!;
    handlers['upload'] = (p, r, a) => _handleUpload(r, node, r.url.queryParameters['key']);
    handlers['getDownloadUrl'] = (p, r, a) => _handleGetDownloadUrl(r, runtime);
    handlers['delete'] = (p, r, a) => _handleDeleteStorage(r, node);
    handlers['readText'] = (p, r, a) => _handleReadText(r, runtime);
    handlers['list'] = (p, r, a) =>
        _handleListObjects(r, node, r.url.queryParameters['prefix']);
    handlers['serveFile'] = (p, r, a) =>
        _handleServeFile(r, node, r.url.queryParameters['uri']);
  }

  return (Request request) async {
    try {
      final path = request.url.path;
      final base = basePath.startsWith('/') ? basePath.substring(1) : basePath;
      final rel = base.isNotEmpty && path.startsWith(base)
          ? path.substring(base.length)
          : path;
      final routePath = rel.startsWith('/') ? rel : '/$rel';
      final match = router.find(request.method, routePath);
      if (match == null) return _json({'error': 'Not found'}, 404);

      final handler = handlers[match.name];
      if (handler == null) {
        return _json({'error': 'Handler not found'}, 500);
      }
      return await handler(match.params, request, api);
    } on HandlerBadRequestError catch (e) {
      return _json({'error': e.message}, 400);
    } catch (e) {
      return _json(
        {
          'error': 'Internal server error',
          'message': e.toString(),
        },
        500,
      );
    }
  };
}

Future<Response> _handleUpload(
  Request request,
  NodeStorageProfile node,
  String? key,
) async {
  if (key == null || key.isEmpty) {
    throw HandlerBadRequestError('Missing query parameter: key');
  }
  final bytes = await request.read().expand((e) => e).toList();
  final safeKey = key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final tmp = File('${Directory.systemTemp.path}/fp_upload_${safeKey}_'
      '${DateTime.now().microsecondsSinceEpoch}.tmp');
  await tmp.writeAsBytes(bytes);
  try {
    final result = await node.upload(key, tmp.path);
    final storageUri = result['storageUri'];
    if (storageUri == null) {
      throw HandlerBadRequestError('Storage did not return a storageUri');
    }
    return _json({'storageUri': storageUri}, 201);
  } finally {
    if (tmp.existsSync()) await tmp.delete();
  }
}

Future<Response> _handleGetDownloadUrl(
  Request request,
  RuntimeStorageProfile runtime,
) async {
  final decoded = jsonDecode(await request.readAsString()) as Map;
  final storageUri = decoded['storageUri'] as String?;
  if (storageUri == null || storageUri.isEmpty) {
    throw HandlerBadRequestError('Missing field: storageUri');
  }
  final result = await runtime.getDownloadUrl(storageUri);
  final fileUrl = result['fileUrl'];
  if (fileUrl == null) {
    throw HandlerBadRequestError('Storage did not return a fileUrl');
  }
  return _json({'fileUrl': fileUrl}, 200);
}

Future<Response> _handleDeleteStorage(
  Request request,
  NodeStorageProfile node,
) async {
  final decoded = jsonDecode(await request.readAsString()) as Map;
  final storageUri = decoded['storageUri'] as String?;
  if (storageUri == null || storageUri.isEmpty) {
    throw HandlerBadRequestError('Missing field: storageUri');
  }
  await node.delete(storageUri);
  return _json({'success': true}, 200);
}

Future<Response> _handleReadText(
  Request request,
  RuntimeStorageProfile runtime,
) async {
  final decoded = jsonDecode(await request.readAsString()) as Map;
  final storageUri = decoded['storageUri'] as String?;
  if (storageUri == null || storageUri.isEmpty) {
    throw HandlerBadRequestError('Missing field: storageUri');
  }
  final text = await runtime.readText(storageUri);
  return _json({'data': text}, 200);
}

Future<Response> _handleListObjects(
  Request request,
  NodeStorageProfile node,
  String? prefix,
) async {
  final objects = await node.listObjects(prefix);
  return _json(
    {
      'data': objects
          .map((o) => {
                'key': o.key,
                'storageUri': o.storageUri,
                'size': o.size,
              })
          .toList(),
    },
    200,
  );
}

Future<Response> _handleServeFile(
  Request request,
  NodeStorageProfile node,
  String? storageUri,
) async {
  if (storageUri == null || storageUri.isEmpty) {
    throw HandlerBadRequestError('Missing query parameter: uri');
  }
  final tmp = File('${Directory.systemTemp.path}/fp_serve_'
      '${storageUri.hashCode}.tmp');
  await node.downloadFile(storageUri, tmp.path);
  try {
    final bytes = await tmp.readAsBytes();
    return Response.ok(
      bytes,
      headers: {'content-type': 'application/octet-stream'},
    );
  } finally {
    if (tmp.existsSync()) await tmp.delete();
  }
}
