import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show
        AppUpdateAvailableInfo,
        AppUpdateInfo,
        AppUpToDateInfo,
        AppUpdateStatus,
        nilUuid,
        PatchInfo,
        Platform,
        UpdateStatus,
        UpdateStrategy;

/// HTTP GET-json function used by [ServerUpdateSource].
///
/// Implementations must return a `Map` for a successful update-check response,
/// or an **empty** `Map` (`{}`) for the legacy "no update" contract where the
/// server responds with a `null` JSON body.
typedef GetJson = Future<Map<String, dynamic>> Function(
  String url, {
  Map<String, String>? headers,
  required Duration timeout,
});

/// Thin [HttpClient]-based [GetJson] used when no injector is supplied.
Future<Map<String, dynamic>> defaultGetJson(
  String url, {
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final uri = Uri.parse(url);
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(uri).timeout(timeout);
    headers?.forEach(req.headers.set);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final resp = await req.close().timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode} from $url');
    }
    final body = await resp.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded == null) return const {};
    if (decoded is! Map) {
      throw FormatException('Invalid update-check JSON from $url: $body');
    }
    return Map<String, dynamic>.from(decoded);
  } finally {
    client.close(force: true);
  }
}

/// Configuration for talking to a flutter_patcher server (or any
/// hot-updater-compatible update-check endpoint).
class ServerUpdateConfig {
  const ServerUpdateConfig({
    required this.baseUrl,
    this.basePath = '/api',
    required this.channel,
    required this.platform,
    required this.updateStrategy,
    this.appVersion,
    this.fingerprintHash,
    this.cohort,
    this.sdkVersion = '1.0.0',
    this.extraHeaders = const {},
  });

  /// Server origin, no trailing slash. e.g. `https://patches.example.com`.
  final String baseUrl;

  /// API mount path. Defaults to `/api` (matches the shelf server default).
  final String basePath;

  /// Deployment channel (e.g. `production`, `staging`).
  final String channel;

  /// Device platform sent to the server.
  final Platform platform;

  /// Targeting strategy: `fingerprint` (hash baked at build) or `appVersion`.
  final UpdateStrategy updateStrategy;

  /// Required when [updateStrategy] is [UpdateStrategy.appVersion].
  final String? appVersion;

  /// Required when [updateStrategy] is [UpdateStrategy.fingerprint].
  final String? fingerprintHash;

  /// Optional cohort segment (deterministic rollout bucketing).
  final String? cohort;

  /// Sent as the `hot-updater-sdk-version` header. `>= 0.31.0` enables the
  /// explicit `{"status":"UP_TO_DATE"}` response.
  final String sdkVersion;

  /// Extra headers (auth tokens, etc.).
  final Map<String, String> extraHeaders;
}

/// Rich result of an update check.
class ServerUpdateResult {
  const ServerUpdateResult({
    required this.isUpToDate,
    this.patch,
    this.status = AppUpdateStatus.upToDate,
    this.shouldForceUpdate = false,
    this.id,
    this.message,
    this.raw = const {},
  });

  /// No update available (or an explicit up-to-date response).
  factory ServerUpdateResult.upToDate() =>
      const ServerUpdateResult(isUpToDate: true);

  final bool isUpToDate;

  /// Installable payload, when an update (or forced rollback) is available.
  final PatchInfo? patch;

  /// `update` | `rollback` | `upToDate`.
  final AppUpdateStatus status;

  /// The server wants this applied even if the device would normally skip it.
  final bool shouldForceUpdate;

  final String? id;
  final String? message;
  final Map<String, dynamic> raw;

  bool get hasUpdate => !isUpToDate && patch != null;
}

/// Client that performs the hot-updater-compatible update check and maps the
/// response to a [PatchInfo] the device SDK can install via
/// `FlutterPatcher.applyPatch`.
///
/// It is backend-agnostic: the same server contract is served by the
/// `flutter_patcher_server` shelf app (backed by any database/storage plugin)
/// or by the Supabase Edge Function mirror.
class ServerUpdateSource {
  ServerUpdateSource({GetJson? getJson}) : _getJson = getJson ?? defaultGetJson;
  final GetJson _getJson;

  /// Builds the update-check URL for [config].
  ///
  /// Paths (relative to [ServerUpdateConfig.basePath]):
  /// - fingerprint: `/fingerprint/:platform/:fingerprintHash/:channel/:minBundleId/:bundleId[/:cohort]`
  /// - appVersion:  `/app-version/:platform/:appVersion/:channel/:minBundleId/:bundleId[/:cohort]`
  ///
  /// `minBundleId`/`bundleId` default to the NIL uuid on first install.
  String buildUrl(ServerUpdateConfig config, {String? currentBundleId}) {
    final base = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    final bp =
        config.basePath.startsWith('/') ? config.basePath : '/${config.basePath}';
    final minBundleId = currentBundleId ?? nilUuid;
    final bundleId = currentBundleId ?? nilUuid;
    final seg = config.updateStrategy == UpdateStrategy.fingerprint
        ? 'fingerprint/${config.platform.value}/${config.fingerprintHash}/${config.channel}/$minBundleId/$bundleId'
        : 'app-version/${config.platform.value}/${config.appVersion}/${config.channel}/$minBundleId/$bundleId';
    final url = '$base$bp/$seg';
    return (config.cohort != null && config.cohort!.isNotEmpty)
        ? '$url/${config.cohort}'
        : url;
  }

  /// Performs the update check and maps the response to a [ServerUpdateResult].
  Future<ServerUpdateResult> check(
    ServerUpdateConfig config, {
    String? currentBundleId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final url = buildUrl(config, currentBundleId: currentBundleId);
    final headers = <String, String>{
      'hot-updater-sdk-version': config.sdkVersion,
      ...config.extraHeaders,
    };
    final decoded =
        await _getJson(url, headers: headers, timeout: timeout);

    // Legacy contract: empty body means "up to date".
    if (decoded.isEmpty) return ServerUpdateResult.upToDate();

    final info = AppUpdateInfo.fromJson(decoded);
    if (info is AppUpToDateInfo) return ServerUpdateResult.upToDate();

    final avail = info as AppUpdateAvailableInfo;
    final fileUrl = avail.fileUrl;
    if (fileUrl == null || fileUrl.isEmpty) {
      return ServerUpdateResult.upToDate();
    }

    final patch = PatchInfo(
      version: avail.id,
      patchUrl: fileUrl,
      md5: avail.fileHash ?? '',
      signature: (decoded['signature'] as String?) ?? '',
      targetVersionCode: null,
      raw: decoded,
    );

    return ServerUpdateResult(
      isUpToDate: false,
      patch: patch,
      status: avail.status == UpdateStatus.rollback
          ? AppUpdateStatus.rollback
          : AppUpdateStatus.update,
      shouldForceUpdate: avail.shouldForceUpdate,
      id: avail.id,
      message: avail.message,
    );
  }
}
