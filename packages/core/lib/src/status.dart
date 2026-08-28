/// Update status enums — hot-updater `UpdateStatus` / `AppUpdateStatus`.
library;

enum UpdateStatus {
  rollback('ROLLBACK'),
  update('UPDATE');

  final String value;
  const UpdateStatus(this.value);

  static UpdateStatus fromValue(String v) => UpdateStatus.values
      .firstWhere((s) => s.value == v,
          orElse: () => throw ArgumentError('unknown status: $v'));
}

/// What the client derives: UP_TO_DATE | ROLLBACK | UPDATE.
enum AppUpdateStatus {
  upToDate('UP_TO_DATE'),
  rollback('ROLLBACK'),
  update('UPDATE');

  final String value;
  const AppUpdateStatus(this.value);
}
