import 'package:flutter_ota_kit/src/pkg/core/flutter_ota_kit_core.dart';
import 'package:flutter_ota_kit/src/pkg/plugin_core/src/get_update_info.dart';
import 'package:test/test.dart';

/// Production-safety audit regression tests.
///
/// Contract notes established during the OTA incident review:
///
/// * A patched device reports its **server bundle UUID** as its identity:
///   `performSharedUpdateCheck` builds `PatchInfo(version: info.id)` (the
///   UUID), native stores that as meta `version`, and `currentVersion()` feeds
///   it back into the next check — so the server's ROLLBACK machinery is
///   addressable. (Verified live: a device id above all enabled bundles
///   receives `status: ROLLBACK` from `get_update_info_by_app_version`.)
/// * A pre-fix client bug compared the `UpdateStatus` enum to the string
///   `'ROLLBACK'`, silently swallowing every rollback response; locked in by
///   `cohort_and_rollback_test.dart`.
/// * `rolloutCohortCount < 1000` with a NULL cohort excludes the device —
///   verified against the live `is_cohort_eligible` SQL (500 -> false,
///   1000 -> true). Devices therefore need a cohort; the SDK now derives one
///   from the native install id.
Bundle _bundle({
  required String id,
  String? targetAppVersion = '1.0.0',
  bool enabled = true,
  int? rolloutCohortCount,
  List<String>? targetCohorts,
}) => Bundle(
  id: id,
  platform: Platform.android,
  shouldForceUpdate: false,
  enabled: enabled,
  fileHash: 'hash',
  storageUri: 'storage://my-app/bundle.zip',
  channel: 'production',
  targetAppVersion: targetAppVersion,
  message: 'hello',
  rolloutCohortCount: rolloutCohortCount,
  targetCohorts: targetCohorts,
);

AppVersionGetBundlesArgs _args({String bundleId = nilUuid, String? cohort}) =>
    AppVersionGetBundlesArgs(
      platform: Platform.android,
      bundleId: bundleId,
      minBundleId: nilUuid,
      channel: 'production',
      cohort: cohort,
      appVersion: '1.0.0',
    );

void main() {
  group('bundle-id / rollback audit', () {
    test('a pristine device (nil identity — nothing applied yet) gets no '
        'rollback signal', () async {
      final bundles = [
        _bundle(id: '00000000-0000-0000-0000-000000000001', enabled: false),
      ];
      // A fresh install has never applied a bundle, so nil identity is
      // correct and there is legitimately nothing to roll back to.
      final update = await getUpdateInfo(bundles, _args());

      expect(
        update,
        isNull,
        reason: 'nil bundle id + no enabled candidates => no signal',
      );
    });

    test(
      'a nil-UUID device with no bundles at all also gets no signal',
      () async {
        expect(await getUpdateInfo([], _args()), isNull);
      },
    );

    test('when the UUID is known (the design intent) disabling the running '
        'bundle DOES produce a rollback', () async {
      final runningId = '00000000-0000-0000-0000-000000000009';
      final bundles = [_bundle(id: runningId, enabled: false)];

      final update = await getUpdateInfo(bundles, _args(bundleId: runningId));

      expect(update, isNotNull);
      expect(update!.status, UpdateStatus.rollback);
      expect(update.shouldForceUpdate, isTrue);
    });
  });

  group('staged-rollout cohort audit', () {
    test(
      'null cohort is excluded from a partial rollout (SQL-verified)',
      () async {
        expect(isCohortEligibleForUpdate('bundle-a', null, 500, null), isFalse);

        final bundles = [
          _bundle(
            id: '00000000-0000-0000-0000-000000000001',
            rolloutCohortCount: 500,
          ),
        ];
        expect(
          await getUpdateInfo(bundles, _args()),
          isNull,
          reason: 'a 50% rollout serves nothing to a device with no cohort',
        );
      },
    );

    test('null cohort is served by a full rollout', () async {
      expect(isCohortEligibleForUpdate('bundle-a', null, 1000, null), isTrue);

      final bundles = [
        _bundle(
          id: '00000000-0000-0000-0000-000000000001',
          rolloutCohortCount: 1000,
        ),
      ];
      final update = await getUpdateInfo(bundles, _args());
      expect(update, isNotNull);
      expect(update!.status, UpdateStatus.update);
    });

    test('an explicit cohort is admitted to a partial rollout', () {
      // Verified against the live Supabase `is_cohort_eligible` function for
      // bundle 01a0e810-…: cohort '750'/500 => true, cohort '5'/500 => false.
      // (SQL and the Dart port agree for a real UUID input.)
      const bundleUuid = '01a0e810-53ea-7a0e-bf23-b25dc0230ce3';
      expect(isCohortEligibleForUpdate(bundleUuid, '750', 500, null), isTrue);
      expect(isCohortEligibleForUpdate(bundleUuid, '5', 500, null), isFalse);
    });
  });
}
