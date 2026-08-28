import 'dart:async';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show EventChannel;
import 'package:flutter/widgets.dart';

import 'src/blacklist.dart';
import 'src/boot_diagnostic.dart';
import 'src/io_stub.dart' if (dart.library.io) 'src/io.dart' as platform_io;
import 'src/patch_info.dart';
import 'src/patcher_channel.dart';
import 'package:flutter_patcher_client/flutter_patcher_client.dart'
    show ServerUpdateConfig, ServerUpdateResult, ServerUpdateSource;
import 'src/supabase_update_source.dart'
    show SupabaseUpdateConfig, SupabaseUpdateSource;
import 'src/postgres_update_source.dart'
    show PostgresUpdateConfig, PostgresUpdateSource;
import 'src/cloudflare_update_source.dart'
    show CloudflareUpdateConfig, CloudflareUpdateSource;
import 'src/aws_update_source.dart' show AwsUpdateConfig, AwsUpdateSource;

export 'src/blacklist.dart';
export 'src/boot_diagnostic.dart';
export 'src/patch_info.dart';
export 'src/supabase_update_source.dart'
    show SupabaseUpdateConfig, SupabaseUpdateSource;
export 'src/postgres_update_source.dart'
    show PostgresUpdateConfig, PostgresUpdateSource;
export 'src/cloudflare_update_source.dart'
    show CloudflareUpdateConfig, CloudflareUpdateSource;
export 'src/aws_update_source.dart' show AwsUpdateConfig, AwsUpdateSource;
export 'package:flutter_patcher_client/flutter_patcher_client.dart';
export 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show Platform, UpdateStrategy;

/// Android-only Flutter hot-update entrypoint.
///
/// `flutter_patcher` installs a patch payload and loads it on the next cold
/// start. The payload can be a legacy `libapp.so` or a v2 `patch.zip` that
/// contains `libapp.so` plus explicitly selected Flutter assets.
///
/// Main APIs:
///
/// - [init]: configure native startup, crash protection, and first-frame boot
///   verification.
/// - [checkUpdate]: optional helper for the built-in minimal update protocol.
/// - [applyPatch]: download, verify, and install a payload URL.
/// - [applyPatchBytes]: install an already downloaded payload byte array.
/// - [rollback]: delete the current patch.
///
/// Patches are never swapped into the current process. A successful apply takes
/// effect only after the next cold start.
///
/// {@category Architecture}
/// {@category API-reference}
/// {@category Crash-protection}
class FlutterPatcher {
  FlutterPatcher._();

  static bool _inited = false;
  static ServerUpdateConfig? _serverConfig;
  static SupabaseUpdateConfig? _supabaseConfig;
  static PostgresUpdateConfig? _postgresConfig;
  static CloudflareUpdateConfig? _cloudflareConfig;
  static AwsUpdateConfig? _awsConfig;
  static bool _bootReported = false;
  static bool _bootErrorReported = false;
  static bool _nonAndroidWarned = false;

  /// Whether Dart boot-error hooks can still report failures to native crash
  /// protection. The first frame clears native boot state immediately; this
  /// flag keeps Dart-side blank-screen detection alive for [init]'s
  /// `verifyAfter` window.
  static bool _dartHookActive = true;

  static bool _notAndroidGuard(String method) {
    if (platform_io.isAndroid) return false;
    if (!_nonAndroidWarned) {
      _nonAndroidWarned = true;
      debugPrint(
        '[FlutterPatcher] WARNING: $method called on ${platform_io.operatingSystem}. '
        'This plugin only supports Android; all calls are no-ops. '
        'See README > What Can Be Patched?',
      );
    }
    return true;
  }

  static const EventChannel _eventChannel = EventChannel(
    'flutter_patcher/events',
  );
  static Stream<PatchApplyProgress>? _progressStream;

  /// Broadcast progress stream for [applyPatch].
  ///
  /// Subscribe before calling [applyPatch] to receive `downloading`,
  /// `verifying`, and `finalizing` events. Non-Android platforms return an
  /// empty stream.
  static Stream<PatchApplyProgress> get applyProgress {
    if (_notAndroidGuard('applyProgress')) return const Stream.empty();
    return _progressStream ??= _eventChannel.receiveBroadcastStream().map(
          (raw) => PatchApplyProgress.fromNative(raw),
        );
  }

  /// Initializes patch configuration and crash protection.
  ///
  /// Call this in `main()` before `runApp()`. The method is idempotent.
  ///
  /// [publicKeyBase64] is an optional X.509 SubjectPublicKeyInfo Ed25519 public
  /// key in base64. Empty disables signature verification. If [PatchInfo.md5]
  /// is empty, signature verification is skipped as well because the signed
  /// message is the md5 hex string.
  ///
  /// [maxCrashCount] defaults to `1` (fail-fast). Once a loaded patch causes an
  /// early boot failure, the SDK rolls it back and blacklists the same payload.
  ///
  /// [strictSignature] rejects signed patches on Android API < 33, where the
  /// platform Ed25519 implementation is unavailable.
  ///
  /// [loaderFieldCandidates] and [loaderFallbackHeuristic] are advanced Flutter
  /// embedding compatibility controls. Keep defaults unless adapting a new
  /// Flutter version.
  ///
  /// [verifyAfter] is the post-first-frame Dart error watch window.
  static Future<void> init({
    String publicKeyBase64 = '',
    int maxCrashCount = 1,
    bool strictSignature = true,
    List<String> loaderFieldCandidates = const ['flutterLoader'],
    bool loaderFallbackHeuristic = false,
    Duration verifyAfter = const Duration(seconds: 5),
  }) async {
    if (_notAndroidGuard('init')) return;
    if (_inited) return;
    _inited = true;
    _verifyAfter = verifyAfter;

    try {
      await PatcherChannel.markBooting();
    } catch (e, s) {
      _log('markBooting failed: $e', s);
    }

    _installBootErrorCatchers();

    try {
      await PatcherChannel.saveConfig(
        publicKeyBase64: publicKeyBase64,
        maxCrashCount: maxCrashCount,
        strictSignature: strictSignature,
        loaderFieldCandidates: loaderFieldCandidates,
        loaderFallbackHeuristic: loaderFallbackHeuristic,
      );
    } catch (e, s) {
      _log('saveConfig failed: $e', s);
    }

    _BootVerifier.start();
  }

  /// Marks the current patched boot as successful and clears native crash
  /// protection state.
  ///
  /// Usually called automatically by [init] after the first frame.
  static Future<void> reportBootSuccess() async {
    if (_notAndroidGuard('reportBootSuccess')) return;
    if (_bootReported) return;
    _bootReported = true;
    try {
      await PatcherChannel.reportBootSuccess();
    } catch (e, s) {
      _log('reportBootSuccess failed: $e', s);
    }
  }

  /// Optional HTTP update checker for the built-in minimal JSON protocol.
  ///
  /// Production apps can skip this method, parse their own update response, and
  /// construct [PatchInfo] directly before calling [applyPatch].
  ///
  /// The returned `patchUrl` is a payload URL: `libapp.so` for lib-only patches
  /// or `patch.zip` for asset patches.
  static Future<PatchCheckResult> checkUpdate(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_notAndroidGuard('checkUpdate')) {
      return PatchCheckResult.none();
    }

    try {
      final decoded = await platform_io.getJson(
        url,
        headers: headers,
        timeout: timeout,
      );
      return PatchCheckResult.fromJson(decoded);
    } on PatcherException {
      rethrow;
    } catch (e, s) {
      _log('checkUpdate failed: $e', s);
      throw PatcherException(e.toString());
    }
  }

  /// Configures the built-in server-backed update source.
  ///
  /// After calling this, [checkForUpdate] performs a hot-updater-compatible
  /// update check against the configured server (which is itself backed by any
  /// database/storage plugin — Supabase, Postgres, Cloudflare, AWS, ...).
  ///
  /// ```dart
  /// FlutterPatcher.configureServer(ServerUpdateConfig(
  ///   baseUrl: 'https://patches.example.com',
  ///   channel: 'production',
  ///   platform: Platform.android,
  ///   updateStrategy: UpdateStrategy.fingerprint,
  ///   fingerprintHash: kBuildFingerprintHash, // baked at build time
  /// ));
  /// ```
  static void configureServer(ServerUpdateConfig config) {
    _serverConfig = config;
  }

  /// Configures the hosted **Supabase** update source.
  ///
  /// Unlike [configureServer], this talks to the Supabase project directly over
  /// its REST API (PostgREST `bundles` table + Storage signed URLs) — no
  /// separate server process is required, because Supabase *is* the backend.
  ///
  /// ```dart
  /// FlutterPatcher.configureSupabase(SupabaseUpdateConfig(
  ///   supabaseUrl: 'https://<ref>.supabase.co',
  ///   anonKey: '<anon>',          // public anon key (RLS-protected reads)
  ///   bucket: 'bundles',
  ///   channel: 'production',
  ///   platform: Platform.android,
  ///   updateStrategy: UpdateStrategy.appVersion,
  ///   appVersion: '1.0.0',
  /// ));
  /// ```
  static void configureSupabase(SupabaseUpdateConfig config) {
    _supabaseConfig = config;
  }

  /// Configures the **Postgres** update source (direct, no server).
  ///
  /// Talks to a Postgres database for bundle metadata and the bytea-backed
  /// storage plugin for artifacts. For HTTP downloads, provide [PostgresUpdateConfig.servingBaseUrl]
  /// (a proxy in front of the `flutter_patcher_storage` table) or use a PostgREST
  /// layer. See `flutter_patcher_postgres` for the backend plugin used by the CLI.
  static void configurePostgres(PostgresUpdateConfig config) {
    _postgresConfig = config;
  }

  /// Configures the **Cloudflare** update source (direct, no server).
  ///
  /// Uses Cloudflare D1 for bundle metadata and R2 (S3-compatible) for artifact
  /// storage. Presigned R2 download URLs are resolved on the device.
  static void configureCloudflare(CloudflareUpdateConfig config) {
    _cloudflareConfig = config;
  }

  /// Configures the **AWS S3** update source (direct, no server).
  ///
  /// Uses an S3-backed blob database for bundle metadata and S3 (presigned URLs,
  /// optionally fronted by CloudFront) for artifact storage.
  static void configureAws(AwsUpdateConfig config) {
    _awsConfig = config;
  }

  /// Performs a server-backed update check using the config from
  /// [configureServer].
  ///
  /// Returns a [ServerUpdateResult]; when [ServerUpdateResult.hasUpdate] is
  /// true, install it with `FlutterPatcher.applyPatch(result.patch!)`.
  static Future<ServerUpdateResult> checkForUpdate({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final currentBundleId = await currentVersion;

    final supabaseConfig = _supabaseConfig;
    if (supabaseConfig != null) {
      return SupabaseUpdateSource().check(
        supabaseConfig,
        currentBundleId: currentBundleId,
      );
    }
    final postgresConfig = _postgresConfig;
    if (postgresConfig != null) {
      return PostgresUpdateSource().check(
        postgresConfig,
        currentBundleId: currentBundleId,
      );
    }
    final cloudflareConfig = _cloudflareConfig;
    if (cloudflareConfig != null) {
      return CloudflareUpdateSource().check(
        cloudflareConfig,
        currentBundleId: currentBundleId,
      );
    }
    final awsConfig = _awsConfig;
    if (awsConfig != null) {
      return AwsUpdateSource().check(
        awsConfig,
        currentBundleId: currentBundleId,
      );
    }
    final config = _serverConfig;
    if (config == null) {
      throw PatcherException(
        'No update source configured. Call FlutterPatcher.configureServer(...), '
        'configureSupabase(...), configurePostgres(...), configureCloudflare(...), '
        'or configureAws(...) first.',
      );
    }
    return ServerUpdateSource().check(
      config,
      currentBundleId: currentBundleId,
      timeout: timeout,
    );
  }

  /// Downloads, verifies, and installs [patchInfo]'s payload.
  ///
  /// The payload can be either a complete `libapp.so` or a v2 `patch.zip`.
  /// Native code detects ZIP payloads automatically.
  ///
  /// Flow:
  ///
  /// 1. Download with retry.
  /// 2. Verify payload md5/signature when provided.
  /// 3. Install legacy lib-only payload, or parse and install v2 package.
  /// 4. Commit patch files transactionally for the next cold start.
  ///
  /// Returns a [PatchApplyResult]. `ok=true` means the patch is installed and
  /// will take effect on the next cold start.
  static Future<PatchApplyResult> applyPatch(
    PatchInfo patchInfo, {
    void Function(PatchApplyProgress)? onProgress,
  }) async {
    if (_notAndroidGuard('applyPatch')) {
      return PatchApplyResult.failure(
        PatchApplyError.unknown,
        'not supported on ${platform_io.operatingSystem}',
      );
    }
    StreamSubscription<PatchApplyProgress>? sub;
    if (onProgress != null) {
      sub = applyProgress.listen(onProgress);
    }
    try {
      final native = await PatcherChannel.applyPatch(patchInfo.toJson());
      return PatchApplyResult.fromNative(native);
    } catch (e, s) {
      _log('applyPatch failed: $e', s);
      return PatchApplyResult.failure(PatchApplyError.unknown, e.toString());
    } finally {
      await sub?.cancel();
    }
  }

  static String? _cachedStagingDir;

  /// Installs an already downloaded patch payload.
  ///
  /// Useful for bundled example patches, custom downloaders, or isolate-based
  /// loading. The bytes can be either `libapp.so` or `patch.zip`.
  ///
  /// This helper writes bytes to native cache, computes md5, then reuses
  /// [applyPatch] through a `file://` URL.
  static Future<PatchApplyResult> applyPatchBytes(
    Uint8List bytes, {
    required String version,
    String signature = '',
    int? targetVersionCode,
    void Function(PatchApplyProgress)? onProgress,
  }) async {
    if (_notAndroidGuard('applyPatchBytes')) {
      return PatchApplyResult.failure(
        PatchApplyError.unknown,
        'not supported on ${platform_io.operatingSystem}',
      );
    }
    final dir = _cachedStagingDir ??= (await PatcherChannel.cacheDir()) ?? '';
    if (dir.isEmpty) {
      return PatchApplyResult.failure(
        PatchApplyError.ioError,
        'native cacheDir unavailable',
      );
    }
    String? stagedPath;
    try {
      stagedPath = await platform_io.stagePatchBytes(dir, bytes);
      final md5Hex = crypto.md5.convert(bytes).toString();
      return await applyPatch(
        PatchInfo(
          version: version,
          patchUrl: 'file://$stagedPath',
          md5: md5Hex,
          signature: signature,
          targetVersionCode: targetVersionCode,
        ),
        onProgress: onProgress,
      );
    } catch (e, s) {
      _log('applyPatchBytes failed: $e', s);
      return PatchApplyResult.failure(PatchApplyError.unknown, e.toString());
    } finally {
      try {
        if (stagedPath != null) {
          await platform_io.deleteFileIfExists(stagedPath);
        }
      } catch (_) {
        // Staging cleanup must not block the apply result.
      }
    }
  }

  /// Deletes the current patch. The next cold start uses the APK built-in
  /// version. Manual rollback does not blacklist the patch.
  static Future<void> rollback() async {
    if (_notAndroidGuard('rollback')) return;
    try {
      await PatcherChannel.rollback();
    } catch (e, s) {
      _log('rollback failed: $e', s);
    }
  }

  /// Current host APK versionCode. Returns null on failure/non-Android.
  static Future<int?> get appVersionCode async {
    if (_notAndroidGuard('appVersionCode')) return null;
    try {
      return await PatcherChannel.appVersionCode();
    } catch (_) {
      return null;
    }
  }

  /// Current device ABI. Useful when your backend routes patches per ABI.
  static Future<String> get deviceAbi async {
    if (_notAndroidGuard('deviceAbi')) return '';
    try {
      return await PatcherChannel.deviceAbi() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Patch version currently installed on disk.
  ///
  /// A successful `applyPatch` updates this immediately, but the patch is only
  /// loaded by Flutter after the next cold start. Returns null when no patch is
  /// installed.
  static Future<String?> get currentVersion async {
    if (_notAndroidGuard('currentVersion')) return null;
    try {
      final v = await PatcherChannel.currentVersion();
      if (v == null || v.isEmpty) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Local bad-patch blacklist, ordered from oldest to newest.
  ///
  /// Automatic blacklist triggers include early boot failures, cold-start md5
  /// mismatches, and cold-start signature failures. For asset patches, the md5
  /// is the `patch.zip` payload md5.
  static Future<List<BlacklistEntry>> get blacklist async {
    if (_notAndroidGuard('blacklist')) return const [];
    try {
      final raw = await PatcherChannel.blacklist();
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((m) => BlacklistEntry.fromNative(m))
          .toList(growable: false);
    } catch (e, s) {
      _log('blacklist failed: $e', s);
      return const [];
    }
  }

  /// Clears the local bad-patch blacklist.
  ///
  /// Intended for tests, local debugging, or deliberate operational recovery.
  static Future<void> clearBlacklist() async {
    if (_notAndroidGuard('clearBlacklist')) return;
    try {
      await PatcherChannel.clearBlacklist();
    } catch (e, s) {
      _log('clearBlacklist failed: $e', s);
    }
  }

  /// Last cold-start patch loading diagnostic.
  ///
  /// `applyPatch` reports install-time failures. This getter reports what
  /// happened on the next cold start: version mismatch, md5/signature failure,
  /// crash rollback, loader hook failure, or successful patch load.
  static Future<PatchBootDiagnostic?> get lastBootDiagnostic async {
    if (_notAndroidGuard('lastBootDiagnostic')) return null;
    try {
      final raw = await PatcherChannel.lastBootDiagnostic();
      if (raw == null) return null;
      return PatchBootDiagnostic.fromNative(raw);
    } catch (e, s) {
      _log('lastBootDiagnostic failed: $e', s);
      return null;
    }
  }

  static Duration _verifyAfter = const Duration(seconds: 5);

  static void _installBootErrorCatchers() {
    final priorPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _maybeReportBootError(error, stack);
      return priorPlatformHandler?.call(error, stack) ?? false;
    };

    final priorFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      _maybeReportBootError(details.exception, details.stack);
      (priorFlutterHandler ?? FlutterError.presentError).call(details);
    };
  }

  static void _maybeReportBootError(Object error, StackTrace? stack) {
    if (!_dartHookActive) return;
    if (_bootErrorReported) return;
    _bootErrorReported = true;
    final msg = error.toString();
    _log('boot-phase Dart error captured: $msg', stack);
    PatcherChannel.reportDartBootError(msg).catchError((e) {
      _log('reportDartBootError channel call failed: $e');
    });
  }

  static void _log(String msg, [StackTrace? stack]) {
    if (kDebugMode) {
      debugPrint('[FlutterPatcher] $msg');
    }
  }
}

/// Plugin-wide exception. Wraps network/parsing errors from [FlutterPatcher.checkUpdate].
class PatcherException implements Exception {
  final String message;
  PatcherException(this.message);
  @override
  String toString() => 'PatcherException: $message';
}

class _BootVerifier with WidgetsBindingObserver {
  static _BootVerifier? _instance;

  Duration _foregroundElapsed = Duration.zero;
  DateTime? _resumedAt;
  Timer? _timer;
  bool _windowClosed = false;

  static void start() {
    if (_instance != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _instance ??= _BootVerifier().._begin();
    });
  }

  void _begin() {
    FlutterPatcher.reportBootSuccess();

    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    final state = binding.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) {
      _resumedAt = DateTime.now();
      _scheduleCheck();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_windowClosed) return;
    if (state == AppLifecycleState.resumed) {
      _resumedAt = DateTime.now();
      _scheduleCheck();
    } else {
      if (_resumedAt != null) {
        _foregroundElapsed += DateTime.now().difference(_resumedAt!);
        _resumedAt = null;
      }
      _timer?.cancel();
    }
  }

  void _scheduleCheck() {
    final remaining = FlutterPatcher._verifyAfter - _foregroundElapsed;
    _timer?.cancel();
    if (remaining <= Duration.zero) {
      _closeHookWindow();
      return;
    }
    _timer = Timer(remaining, _closeHookWindow);
  }

  void _closeHookWindow() {
    if (_windowClosed) return;
    _windowClosed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    FlutterPatcher._dartHookActive = false;
  }
}
