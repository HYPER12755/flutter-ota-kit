import 'dart:async';

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show
        AppUpdateStatus,
        AppVersionGetBundlesArgs,
        FingerprintGetBundlesArgs,
        GetBundlesArgs,
        nilUuid,
        Platform,
        UpdateInfo,
        UpdateStrategy;
import 'package:flutter_ota_kit_client/flutter_ota_kit_client.dart'
    show ServerUpdateResult;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show DatabasePlugin, StoragePlugin;
import 'patch_info.dart' show PatchInfo;
import 'app_version_resolver.dart';

final _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Backend-agnostic update-check orchestration shared by every hosted source
/// (Supabase / Postgres / Cloudflare / AWS / PocketBase).
///
/// The only backend-specific pieces are the already-constructed [DatabasePlugin]
/// and [StoragePlugin] plus the targeting fields pulled from each source config.
/// Everything else — bundle-id normalization, `appVersion`/fingerprint argument
/// building (with runtime `appVersion` auto-detection), the `getUpdateInfo` call,
/// download-URL resolution and the `ServerUpdateResult` mapping — is identical
/// across backends and lives here exactly once.
///
/// [timeout] bounds the two HTTP round-trips (DB query + signed-URL mint).
/// When the timeout fires, the in-flight HTTP request is cancelled via
/// `Future.timeout`, which propagates a `TimeoutException` that callers can
/// catch and surface to the user (e.g. "no internet — try again later").
Future<ServerUpdateResult> performSharedUpdateCheck({
  required DatabasePlugin db,
  required StoragePlugin storage,
  required String channel,
  required Platform platform,
  required UpdateStrategy updateStrategy,
  required String? appVersion,
  required String? fingerprintHash,
  required String minBundleId,
  String? currentBundleId,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final bundleId = (currentBundleId != null && _uuidRe.hasMatch(currentBundleId))
      ? currentBundleId
      : nilUuid;

  final GetBundlesArgs args;
  if (updateStrategy == UpdateStrategy.fingerprint) {
    args = FingerprintGetBundlesArgs(
      channel: channel,
      platform: platform,
      bundleId: bundleId,
      minBundleId: minBundleId,
      fingerprintHash: fingerprintHash ?? '',
    );
  } else {
    final resolvedAppVersion = await resolveAppVersion(appVersion);
    args = AppVersionGetBundlesArgs(
      channel: channel,
      platform: platform,
      bundleId: bundleId,
      minBundleId: minBundleId,
      appVersion: resolvedAppVersion,
    );
  }

  final UpdateInfo? info = await db.getUpdateInfo(args).timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'update check timed out after ${timeout.inSeconds}s while querying the backend',
        ),
      );
  if (info == null) return ServerUpdateResult.upToDate();

  final storageUri = info.storageUri;
  if (storageUri == null || storageUri.isEmpty) {
    return ServerUpdateResult.upToDate();
  }

  final runtime = storage.profiles.runtime;
  if (runtime == null) return ServerUpdateResult.upToDate();
  final dl = await runtime.getDownloadUrl(storageUri).timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'update check timed out after ${timeout.inSeconds}s while minting the download URL',
        ),
      );
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
