/// Faithful port of hot-updater `plugins/postgres/src/getUpdateInfo.ts`.
///
/// Calls the PL/pgSQL RPCs (`get_target_app_version_list`,
/// `get_update_info_by_app_version`, `get_update_info_by_fingerprint_hash`)
/// defined in `plugins/postgres/sql/*.sql`. The DB must have those functions
/// installed (see `supabase/migrations` parity work / Phase 5).
library;

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show
        FingerprintGetBundlesArgs,
        GetBundlesArgs,
        AppVersionGetBundlesArgs,
        UpdateInfo,
        UpdateStatus,
        UpdateStrategy;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show filterCompatibleAppVersions;

import 'postgres_client.dart';

/// Row shape returned by the update-info RPCs.
class _UpdateInfoRow {
  const _UpdateInfoRow({
    required this.id,
    required this.shouldForceUpdate,
    required this.message,
    required this.status,
    required this.storageUri,
    required this.fileHash,
  });

  factory _UpdateInfoRow.fromJson(Map<String, dynamic> row) => _UpdateInfoRow(
    id: row['id'] as String,
    shouldForceUpdate: row['should_force_update'] as bool,
    message: row['message'] as String?,
    status: row['status'] as String,
    storageUri: row['storage_uri'] as String?,
    fileHash: row['file_hash'] as String?,
  );

  final String id;
  final bool shouldForceUpdate;
  final String? message;
  final String status;
  final String? storageUri;
  final String? fileHash;
}

UpdateInfo mapUpdateInfoRow(_UpdateInfoRow row) => UpdateInfo(
  id: row.id,
  shouldForceUpdate: row.shouldForceUpdate,
  message: row.message,
  status: row.status == 'ROLLBACK'
      ? UpdateStatus.rollback
      : UpdateStatus.update,
  storageUri: row.storageUri,
  fileHash: row.fileHash,
);

/// Resolve update info via the Postgres RPCs.
Future<UpdateInfo?> getUpdateInfo(
  PostgresClientLike client,
  GetBundlesArgs args,
) async {
  if (args.updateStrategy == UpdateStrategy.appVersion) {
    final appArgs = args as AppVersionGetBundlesArgs;
    final targetRes = await client.execute(
      'SELECT target_app_version '
      'FROM get_target_app_version_list(@app_platform, @min_bundle_id)',
      {
        'app_platform': appArgs.platform.value,
        'min_bundle_id': appArgs.minBundleId,
      },
    );

    final targetAppVersionList = filterCompatibleAppVersions(
      targetRes
          .map((row) => row['target_app_version'] as String?)
          .where((value) => value != null)
          .cast<String>()
          .toList(),
      appArgs.appVersion,
    );

    final res = await client.execute(
      'SELECT * FROM get_update_info_by_app_version('
      '@app_platform, @app_version, @bundle_id, @min_bundle_id, '
      '@target_channel, @target_app_version_list, @cohort)',
      {
        'app_platform': appArgs.platform.value,
        'app_version': appArgs.appVersion,
        'bundle_id': appArgs.bundleId,
        'min_bundle_id': appArgs.minBundleId,
        'target_channel': appArgs.channel,
        'target_app_version_list': targetAppVersionList,
        'cohort': appArgs.cohort,
      },
    );

    if (res.isEmpty) return null;
    return mapUpdateInfoRow(_UpdateInfoRow.fromJson(res.first));
  }

  final fpArgs = args as FingerprintGetBundlesArgs;
  final res = await client.execute(
    'SELECT * FROM get_update_info_by_fingerprint_hash('
    '@app_platform, @bundle_id, @min_bundle_id, '
    '@target_channel, @target_fingerprint_hash, @cohort)',
    {
      'app_platform': fpArgs.platform.value,
      'bundle_id': fpArgs.bundleId,
      'min_bundle_id': fpArgs.minBundleId,
      'target_channel': fpArgs.channel,
      'target_fingerprint_hash': fpArgs.fingerprintHash,
      'cohort': fpArgs.cohort,
    },
  );

  if (res.isEmpty) return null;
  return mapUpdateInfoRow(_UpdateInfoRow.fromJson(res.first));
}
