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
import 'src/ota_progress_overlay.dart' show OtaOverlayManager;
import 'src/flutter_ota_app.dart' show FlutterPatcherShowUpdateUiBinding;
import 'package:flutter_ota_kit_client/flutter_ota_kit_client.dart'
    show ServerUpdateResult;
import 'src/supabase_update_source.dart'
    show SupabaseUpdateConfig, SupabaseUpdateSource;
import 'src/postgres_update_source.dart'
    show PostgresUpdateConfig, PostgresUpdateSource;
import 'src/cloudflare_update_source.dart'
    show CloudflareUpdateConfig, CloudflareUpdateSource;
import 'src/aws_update_source.dart' show AwsUpdateConfig, AwsUpdateSource;
import 'src/pocketbase_update_source.dart'
    show PocketBaseUpdateConfig, PocketBaseUpdateSource;
import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show Platform, UpdateStrategy;

export 'src/blacklist.dart';
export 'src/boot_diagnostic.dart';
export 'src/patch_info.dart';
export 'src/shared_update_check.dart' show performSharedUpdateCheck;
export 'src/supabase_update_source.dart'
    show SupabaseUpdateConfig, SupabaseUpdateSource;
export 'src/postgres_update_source.dart'
    show PostgresUpdateConfig, PostgresUpdateSource;
export 'src/cloudflare_update_source.dart'
    show CloudflareUpdateConfig, CloudflareUpdateSource;
export 'src/aws_update_source.dart' show AwsUpdateConfig, AwsUpdateSource;
export 'src/pocketbase_update_source.dart'
    show PocketBaseUpdateConfig, PocketBaseUpdateSource;
export 'src/flutter_ota_app.dart' show FlutterOtaApp;
export 'src/ota_progress_overlay.dart'
    show OtaOverlayManager, OtaOverlayState, OtaProgressOverlay, OtaOverlayHandle;
export 'package:flutter_ota_kit_client/flutter_ota_kit_client.dart';
export 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show Platform, UpdateStrategy;

/// Android-only Flutter hot-update entrypoint.
///
/// `flutter_ota_kit` installs a patch payload and loads it on the next cold
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
/// - [applyUpdate]: apply a [ServerUpdateResult] and auto-restart if forced.
/// - [restart]: restart the whole App process (used to apply forced updates).
/// - [rollback]: delete the current patch.
///
/// Patches are never swapped into the current process. A successful apply takes
/// effect only after the next cold start. A non-forced update waits for that
/// next cold start; a forced update ([ServerUpdateResult.shouldForceUpdate])
/// is applied immediately via [applyUpdate] -> [restart].
///
/// {@category Architecture}
/// {@category API-reference}
/// {@category Crash-protection}
class FlutterPatcher {
  FlutterPatcher._();

  static bool _inited = false;
  static SupabaseUpdateConfig? _supabaseConfig;
  static PostgresUpdateConfig? _postgresConfig;
  static CloudflareUpdateConfig? _cloudflareConfig;
  static AwsUpdateConfig? _awsConfig;
  static PocketBaseUpdateConfig? _pocketbaseConfig;
  static bool _bootReported = false;
  static bool _bootErrorReported = false;
  static bool _nonAndroidWarned = false;

  /// Whether Dart boot-error hooks can still report failures to native crash
  /// protection. The first frame clears native boot state immediately; this
  /// flag keeps Dart-side blank-screen detection alive for [init]'s
  /// `verifyAfter` window.
  static bool _dartHookActive = true;

  /// When `true` (default), a forced update shows the built-in progress overlay
  /// (terminal-style dot spinner + determinate bar + server OTA message). Set to
  /// `false` to disable it (forced updates still apply, just without UI). Can
  /// also be toggled via [FlutterOtaApp.showUpdateUi] or [navigatorKey].
  static bool showUpdateUi = true;

  /// Optional navigator key. When set on your [MaterialApp.navigatorKey], the
  /// forced-update overlay can be shown even without wrapping the app in
  /// [FlutterOtaApp]. The [FlutterOtaApp] wrapper is the zero-code path.
  static final navigatorKey = GlobalKey<NavigatorState>();

  // Wire the widget-level flag to [showUpdateUi] so [FlutterOtaApp] can toggle it,
  // and let the overlay manager fall back to the consumer-provided navigator key.
  static void _wireOverlay() {
    FlutterPatcherShowUpdateUiBinding.applyShowUpdateUi =
        (value) => showUpdateUi = value;
    OtaOverlayManager.instance.setResolver(
      () => navigatorKey.currentState?.overlay,
    );
  }


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
    'flutter_ota_kit/events',
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
  ///
  /// [autoApplyUpdates] wires zero-click updates: right after boot protection is
  /// initialized, [checkAndApplyUpdates] runs in the background. A forced update
  /// is downloaded, staged, and the process is restarted automatically — no user
  /// tap required. Non-forced updates are staged for the next normal cold start.
  /// The backend must be configured (e.g. via [configureSupabase]) *before*
  /// calling [init] for this to take effect.
  static Future<void> init({
    String publicKeyBase64 = '',
    int maxCrashCount = 1,
    bool strictSignature = true,
    List<String> loaderFieldCandidates = const ['flutterLoader'],
    bool loaderFallbackHeuristic = false,
    Duration verifyAfter = const Duration(seconds: 5),
    bool autoApplyUpdates = false,
  }) async {
    if (_notAndroidGuard('init')) return;
    if (_inited) return;
    _inited = true;
    _verifyAfter = verifyAfter;
    _wireOverlay();

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

    // Auto-configure a backend from build-time environment variables
    // (`--dart-define` / `.env`). No-op when a backend is already configured
    // (e.g. via the generated `flutter_ota_kit_setup.dart` or an explicit
    // `configureX`). Environment wins over the `.flutter_ota_kit/` project config.
    _autoConfigureFromEnv();

    if (autoApplyUpdates) {
      // Fire-and-forget so a forced update applies + restarts without blocking
      // the first frame. Swallowed failures never crash boot.
      unawaited(checkAndApplyUpdates());
    }
  }

  /// Auto-configure a backend from build-time environment variables
  /// (`--dart-define` / `.env` via `--dart-define-from-file`), when no backend
  /// was configured explicitly (e.g. via `configureSupabase` or the generated
  /// `flutter_ota_kit_setup.dart`). This is the second supported config path
  /// alongside the `.flutter_ota_kit/` project config; both honor the same
  /// precedence — environment overrides any file-based default.
  static void _autoConfigureFromEnv() {
    if (_supabaseConfig != null ||
        _postgresConfig != null ||
        _cloudflareConfig != null ||
        _awsConfig != null ||
        _pocketbaseConfig != null) {
      return; // already configured (e.g. generated setup ran first)
    }

    // Optional explicit backend picker. When the user has multiple backends in
    // their .env (e.g. switching from supabase to pocketbase), this var
    // disambiguates which one wins. Without it, first-match-wins order is:
    // supabase → postgres → cloudflare → aws → pocketbase.
    const backendHint = String.fromEnvironment('FLUTTER_OTA_BACKEND', defaultValue: '');
    bool isMatching(String name) {
      if (backendHint.isEmpty) return true;
      return backendHint.toLowerCase() == name;
    }

    const supabaseUrl =
        String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    if (supabaseUrl.isNotEmpty && isMatching('supabase')) {
      _supabaseConfig = SupabaseUpdateConfig(
        supabaseUrl: supabaseUrl,
        anonKey:
            const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: ''),
        bucket: const String.fromEnvironment('SUPABASE_BUCKET',
            defaultValue: 'bundles'),
        channel: const String.fromEnvironment('CHANNEL',
            defaultValue: 'production'),
        platform: Platform.android,
        updateStrategy: UpdateStrategy.appVersion,
        appVersion: const String.fromEnvironment('APP_VERSION',
            defaultValue: '1.0.0'),
        sdkVersion: const String.fromEnvironment('SDK_VERSION',
            defaultValue: '1.0.0'),
      );
      return;
    }

    const pgHost = String.fromEnvironment('POSTGRES_HOST', defaultValue: '');
    const pgDatabaseUrl =
        String.fromEnvironment('DATABASE_URL', defaultValue: '');
    if ((pgHost.isNotEmpty || pgDatabaseUrl.isNotEmpty) &&
        isMatching('postgres')) {
      _postgresConfig = PostgresUpdateConfig(
        host: pgHost,
        port: int.tryParse(const String.fromEnvironment('POSTGRES_PORT',
            defaultValue: '5432')) ?? 5432,
        database: const String.fromEnvironment('POSTGRES_DB',
            defaultValue: 'postgres'),
        username: const String.fromEnvironment('POSTGRES_USER',
            defaultValue: ''),
        password: const String.fromEnvironment('POSTGRES_PASSWORD',
            defaultValue: ''),
        servingBaseUrl: const String.fromEnvironment(
            'POSTGRES_SERVING_BASE_URL',
            defaultValue: ''),
        channel: const String.fromEnvironment('CHANNEL',
            defaultValue: 'production'),
        platform: Platform.android,
        updateStrategy: UpdateStrategy.appVersion,
        appVersion: const String.fromEnvironment('APP_VERSION',
            defaultValue: '1.0.0'),
      );
      return;
    }

    const cfAccount =
        String.fromEnvironment('CLOUDFLARE_ACCOUNT_ID', defaultValue: '');
    if (cfAccount.isNotEmpty && isMatching('cloudflare')) {
      _cloudflareConfig = CloudflareUpdateConfig(
        accountId: cfAccount,
        databaseId: const String.fromEnvironment(
            'CLOUDFLARE_D1_DATABASE_ID',
            defaultValue: ''),
        cloudflareApiToken: const String.fromEnvironment(
            'CLOUDFLARE_API_TOKEN',
            defaultValue: ''),
        bucketName: const String.fromEnvironment('R2_BUCKET',
            defaultValue: 'bundles'),
        accessKeyId: const String.fromEnvironment('R2_ACCESS_KEY_ID',
            defaultValue: ''),
        secretAccessKey: const String.fromEnvironment(
            'R2_SECRET_ACCESS_KEY',
            defaultValue: ''),
        basePath:
            const String.fromEnvironment('R2_BASE_PATH', defaultValue: ''),
        channel: const String.fromEnvironment('CHANNEL',
            defaultValue: 'production'),
        platform: Platform.android,
        updateStrategy: UpdateStrategy.appVersion,
        appVersion: const String.fromEnvironment('APP_VERSION',
            defaultValue: '1.0.0'),
      );
      return;
    }

    const awsBucket = String.fromEnvironment('AWS_BUCKET', defaultValue: '');
    if (awsBucket.isNotEmpty && isMatching('aws')) {
      _awsConfig = AwsUpdateConfig(
        bucketName: awsBucket,
        region:
            const String.fromEnvironment('AWS_REGION', defaultValue: ''),
        accessKeyId: const String.fromEnvironment('AWS_ACCESS_KEY_ID',
            defaultValue: ''),
        secretAccessKey: const String.fromEnvironment(
            'AWS_SECRET_ACCESS_KEY',
            defaultValue: ''),
        basePath:
            const String.fromEnvironment('AWS_BASE_PATH', defaultValue: ''),
        endpoint:
            const String.fromEnvironment('AWS_ENDPOINT', defaultValue: ''),
        channel:
            const String.fromEnvironment('CHANNEL', defaultValue: 'production'),
        platform: Platform.android,
        updateStrategy: UpdateStrategy.appVersion,
        appVersion: const String.fromEnvironment('APP_VERSION',
            defaultValue: '1.0.0'),
      );
      return;
    }

    const pbUrl = String.fromEnvironment('POCKETBASE_URL', defaultValue: '');
    if (pbUrl.isNotEmpty && isMatching('pocketbase')) {
      _pocketbaseConfig = PocketBaseUpdateConfig(
        url: pbUrl,
        adminEmail: const String.fromEnvironment('POCKETBASE_ADMIN_EMAIL',
            defaultValue: ''),
        adminPassword: const String.fromEnvironment(
            'POCKETBASE_ADMIN_PASSWORD',
            defaultValue: ''),
        bundlesCollection: const String.fromEnvironment(
            'POCKETBASE_BUNDLES_COLLECTION',
            defaultValue: 'bundles'),
        bundlesBucket: const String.fromEnvironment('POCKETBASE_BUCKET',
            defaultValue: 'bundles'),
        channel: const String.fromEnvironment('CHANNEL',
            defaultValue: 'production'),
        platform: Platform.android,
        updateStrategy: UpdateStrategy.appVersion,
        appVersion: const String.fromEnvironment('APP_VERSION',
            defaultValue: '1.0.0'),
      );
      return;
    }
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

  /// Configures the hosted **Supabase** update source.
  ///
  /// Talks to the Supabase project directly over its REST API (PostgREST
  /// `bundles` table + Storage signed URLs) — no separate server process is
  /// required, because Supabase *is* the backend.
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
  /// (a proxy in front of the `flutter_ota_kit_storage` table) or use a PostgREST
  /// layer. See `flutter_ota_kit_postgres` for the backend plugin used by the CLI.
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

  /// Configures the **PocketBase** update source (self-hosted, single binary).
  ///
  /// Talks to a PocketBase instance directly over its REST API. PocketBase is a
  /// single-binary Go backend with SQLite + auth + file storage + an admin UI
  /// (~15MB). The schema is installed via `flutter_ota_kit pocketbase serve`.
  ///
  /// PocketBase is the recommended option for small teams that want a
  /// Supabase-like experience without a cloud account — single binary, no
  /// Docker, no external database.
  static void configurePocketBase(PocketBaseUpdateConfig config) {
    _pocketbaseConfig = config;
  }

  /// Performs an update check against the configured backend (Supabase,
  /// Postgres, Cloudflare, AWS, or PocketBase).
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
        timeout: timeout,
      );
    }
    final postgresConfig = _postgresConfig;
    if (postgresConfig != null) {
      return PostgresUpdateSource().check(
        postgresConfig,
        currentBundleId: currentBundleId,
        timeout: timeout,
      );
    }
    final cloudflareConfig = _cloudflareConfig;
    if (cloudflareConfig != null) {
      return CloudflareUpdateSource().check(
        cloudflareConfig,
        currentBundleId: currentBundleId,
        timeout: timeout,
      );
    }
    final awsConfig = _awsConfig;
    if (awsConfig != null) {
      return AwsUpdateSource().check(
        awsConfig,
        currentBundleId: currentBundleId,
        timeout: timeout,
      );
    }
    final pocketbaseConfig = _pocketbaseConfig;
    if (pocketbaseConfig != null) {
      return PocketBaseUpdateSource().check(
        pocketbaseConfig,
        currentBundleId: currentBundleId,
        timeout: timeout,
      );
    }
    throw PatcherException(
      'No update source configured. Call FlutterPatcher.configureSupabase(...), '
      'configurePostgres(...), configureCloudflare(...), configureAws(...), or '
      'configurePocketBase(...) first.',
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

  /// Immediately restarts the whole App process.
  ///
  /// A staged patch only loads on a cold start, so after a forced update the
  /// new code won't run until the process restarts. Call this to apply the
  /// forced update right away instead of waiting for the user to relaunch.
  ///
  /// On non-Android this is a no-op. Failures are swallowed and logged — the
  /// usual fallback is a "please restart" prompt rather than a crash.
  static Future<void> restart() async {
    if (_notAndroidGuard('restart')) return;
    try {
      await PatcherChannel.restartApp();
    } catch (e, s) {
      _log('restart failed: $e', s);
    }
  }

  /// Stage an update from a [ServerUpdateResult] and auto-restart when forced.
  ///
  /// Equivalent to `applyPatch(result.patch)`, then `restart()` **only if**
  /// [ServerUpdateResult.shouldForceUpdate] is true. Non-forced updates are
  /// staged and take effect on the next normal cold start (no restart).
  ///
  /// When [showUpdateUi] is on (default) and the update is forced, a built-in
  /// progress overlay (dot spinner + determinate bar + the server OTA message)
  /// is shown automatically during the download/verify/install — the consuming
  /// app writes no UI. Disable it with [showUpdateUi] = `false` or by wrapping
  /// the app in [FlutterOtaApp(showUpdateUi: false)].
  ///
  /// A developer-supplied [onProgress] callback, if provided, is still invoked
  /// alongside the overlay.
  ///
  /// Returns the [PatchApplyResult] from [applyPatch]. When there is nothing to
  /// apply (`result.patch == null`) it returns a no-op failure result.
  static Future<PatchApplyResult> applyUpdate(
    ServerUpdateResult result, {
    void Function(PatchApplyProgress)? onProgress,
  }) async {
    if (!result.hasUpdate || result.patch == null) {
      _log('applyUpdate: no patch to apply');
      return PatchApplyResult.failure(
        PatchApplyError.unknown,
        'no update available',
      );
    }

    final showOverlay = showUpdateUi && result.shouldForceUpdate;
    final fromVersion = await currentVersion;
    final handle = showOverlay
        ? OtaOverlayManager.instance.begin(
            message: result.message,
            targetVersion: result.id,
            currentVersion: fromVersion,
          )
        : null;

    final applied = await applyPatch(
      result.patch!,
      onProgress: (p) {
        handle?.update(p);
        onProgress?.call(p);
      },
    );

    if (applied.ok && result.shouldForceUpdate) {
      handle?.end();
      await restart();
    } else {
      handle?.end(hasError: !applied.ok, errorText: applied.message);
    }
    return applied;
  }

  /// Checks for an update and applies it, auto-restarting when forced.
  ///
  /// Call this once after [init] (or pass `autoApplyUpdates: true` to [init])
  /// to implement "forced updates apply and restart with zero user taps".
  ///
  /// The update is skipped when the returned patch version already equals the
  /// currently installed patch version ([currentVersion]). This prevents
  /// re-applying — and therefore re-restarting — on every launch once the
  /// device is already on the latest bundle.
  ///
  /// Failures are swallowed and logged so a broken backend can never crash boot.
  static Future<PatchApplyResult?> checkAndApplyUpdates({
    void Function(PatchApplyProgress)? onProgress,
  }) async {
    if (_notAndroidGuard('checkAndApplyUpdates')) return null;
    try {
      final result = await checkForUpdate();
      if (!result.hasUpdate || result.patch == null) {
        _log('checkAndApplyUpdates: no update');
        return null;
      }
      final current = await currentVersion;
      if (current != null && current == result.patch!.version) {
        _log('checkAndApplyUpdates: already on ${result.patch!.version}, skip');
        return null;
      }
      return await applyUpdate(result, onProgress: onProgress);
    } catch (e, s) {
      _log('checkAndApplyUpdates failed: $e', s);
      return null;
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
