import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show nilUuid, Platform, UpdateStrategy;
import 'package:flutter_ota_kit_client/flutter_ota_kit_client.dart'
    show ServerUpdateResult;
import 'package:flutter_ota_kit_supabase/flutter_ota_kit_supabase.dart'
    show
        supabaseDatabase,
        supabaseStorage,
        SupabaseServiceRoleConfig,
        SupabaseStorageConfig;
import 'shared_update_check.dart';

/// Configuration for a hosted **Supabase** update source.
///
/// Talks to the Supabase project directly over its REST API
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
class SupabaseUpdateSource {
  const SupabaseUpdateSource();

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

    return performSharedUpdateCheck(
      db: db,
      storage: storage,
      channel: config.channel,
      platform: config.platform,
      updateStrategy: config.updateStrategy,
      appVersion: config.appVersion,
      fingerprintHash: config.fingerprintHash,
      minBundleId: config.minBundleId,
      currentBundleId: currentBundleId,
    );
  }
}
