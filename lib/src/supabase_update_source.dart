import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show
        AppUpdateStatus,
        AppVersionGetBundlesArgs,
        FingerprintGetBundlesArgs,
        GetBundlesArgs,
        nilUuid,
        Platform,
        UpdateInfo,
        UpdateStrategy;
import 'package:flutter_patcher_client/flutter_patcher_client.dart'
    show ServerUpdateResult;
import 'patch_info.dart' show PatchInfo;
import 'package:flutter_patcher_supabase/flutter_patcher_supabase.dart'
    show
        supabaseDatabase,
        supabaseStorage,
        SupabaseServiceRoleConfig,
        SupabaseStorageConfig;

/// Configuration for a hosted **Supabase** update source.
///
/// Unlike [ServerUpdateConfig] (which points at a self-hosted flutter_patcher
/// server), this talks to the Supabase project directly over its REST API
/// (PostgREST `bundles` table + Storage signed URLs). No separate server is
/// required — Supabase *is* the backend.
class SupabaseUpdateConfig {
  const SupabaseUpdateConfig({
    required this.supabaseUrl,
    this.anonKey,
    this.serviceRoleKey,
    required this.bucket,
    required this.channel,
    required this.platform,
    required this.updateStrategy,
    this.appVersion,
    this.fingerprintHash,
    this.sdkVersion = '1.0.0',
    this.cohort,
    this.minBundleId = nilUuid,
  });

  final String supabaseUrl;
  final String? anonKey;
  final String? serviceRoleKey;
  final String bucket;
  final String channel;
  final Platform platform;
  final UpdateStrategy updateStrategy;
  final String? appVersion;
  final String? fingerprintHash;
  final String sdkVersion;
  final String? cohort;

  /// Build-time scan floor (mirrors hot-updater's `getMinBundleId()`). Bundles
  /// with an id older than this are never served.
  final String minBundleId;
}

/// Device-side update source backed by a hosted Supabase project. Performs the
/// update check directly against PostgREST and resolves the patch download URL
/// from Supabase Storage (signed URL). Mirrors hot-updater's `createSupabaseSource`.
final _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class SupabaseUpdateSource {
  SupabaseUpdateSource();

  /// Reads the latest enabled bundle for the configured channel/platform/target
  /// and resolves its download URL.
  Future<ServerUpdateResult> check(
    SupabaseUpdateConfig config, {
    String? currentBundleId,
  }) async {
    final dbConfig = SupabaseServiceRoleConfig(
      supabaseUrl: config.supabaseUrl,
      supabaseServiceRoleKey: config.serviceRoleKey,
      supabaseAnonKey: config.anonKey,
    );
    final storageConfig = SupabaseStorageConfig(
      supabaseUrl: config.supabaseUrl,
      supabaseServiceRoleKey: config.serviceRoleKey,
      supabaseAnonKey: config.anonKey,
      bucketName: config.bucket,
    );

    final db = supabaseDatabase(dbConfig)();
    final storage = supabaseStorage(storageConfig);

    final bundleId = (currentBundleId != null && _uuidRe.hasMatch(currentBundleId))
        ? currentBundleId
        : nilUuid;

    final GetBundlesArgs args;
    if (config.updateStrategy == UpdateStrategy.fingerprint) {
      args = FingerprintGetBundlesArgs(
        channel: config.channel,
        platform: config.platform,
        bundleId: bundleId,
        minBundleId: config.minBundleId,
        fingerprintHash: config.fingerprintHash ?? '',
      );
    } else {
      args = AppVersionGetBundlesArgs(
        channel: config.channel,
        platform: config.platform,
        bundleId: bundleId,
        minBundleId: config.minBundleId,
        appVersion: config.appVersion ?? '',
      );
    }

    final UpdateInfo? info = await db.getUpdateInfo(args);
    if (info == null) return ServerUpdateResult.upToDate();

    final storageUri = info.storageUri;
    if (storageUri == null || storageUri.isEmpty) {
      return ServerUpdateResult.upToDate();
    }

    final runtime = storage.profiles.runtime;
    if (runtime == null) return ServerUpdateResult.upToDate();
    final dl = await runtime.getDownloadUrl(storageUri);
    final fileUrl = dl['fileUrl'];
    if (fileUrl == null || fileUrl.isEmpty) {
      return ServerUpdateResult.upToDate();
    }

    final patch = PatchInfo(
      version: info.id,
      patchUrl: fileUrl,
      md5: info.fileHash ?? '',
    );
    return ServerUpdateResult(
      isUpToDate: false,
      patch: patch,
      status: AppUpdateStatus.update,
      shouldForceUpdate: info.shouldForceUpdate,
      id: info.id,
      message: info.message,
    );
  }
}
