/// Update status enums — hot-updater `UpdateStatus` / `AppUpdateStatus`.
///
/// [UpdateStatus] is used in database rows to mark bundles as deployed or
/// rolled back. [AppUpdateStatus] is derived by the client SDK to indicate
/// the result of an update check.
library;

/// Server-side deployment status for a bundle.
enum UpdateStatus {
  /// Bundle has been rolled back (no longer served to devices).
  rollback('ROLLBACK'),

  /// Bundle is active and served to eligible devices.
  update('UPDATE');

  /// String value stored in database rows.
  final String value;

  const UpdateStatus(this.value);

  /// Parse an update status string. Throws [ArgumentError] if [v] is not
  /// a recognized status value.
  static UpdateStatus fromValue(String v) => UpdateStatus.values.firstWhere(
    (s) => s.value == v,
    orElse: () => throw ArgumentError('unknown status: $v'),
  );
}

/// Client-side update check result.
enum AppUpdateStatus {
  /// Device is already on the latest bundle for its channel/platform.
  upToDate('UP_TO_DATE'),

  /// Device should roll back to a previous bundle.
  rollback('ROLLBACK'),

  /// Device should download and install a new bundle.
  update('UPDATE');

  /// String value returned in update-check API responses.
  final String value;

  const AppUpdateStatus(this.value);
}
