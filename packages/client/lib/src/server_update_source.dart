import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show PatchInfo, AppUpdateStatus;

/// Rich result of an update check. Returned by every backend source
/// (`SupabaseUpdateSource`, `PostgresUpdateSource`, `CloudflareUpdateSource`,
/// `AwsUpdateSource`) so callers can treat all backends uniformly.
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
