import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
import 'package:flutter_ota_kit_plugin_core/src/get_update_info.dart';
import 'package:test/test.dart';

const _defaultBundleMessage = 'hello';
const _defaultStorageUri = 'storage://my-app/bundle.zip';
const _defaultFileHash = 'hash';

Bundle _appVersionBundle({
  required String id,
  String? targetAppVersion,
  bool enabled = true,
  bool shouldForceUpdate = false,
  String channel = 'production',
  String? message,
  int? rolloutCohortCount,
  List<String>? targetCohorts,
}) =>
    Bundle(
      id: id,
      platform: Platform.android,
      shouldForceUpdate: shouldForceUpdate,
      enabled: enabled,
      fileHash: _defaultFileHash,
      storageUri: _defaultStorageUri,
      channel: channel,
      targetAppVersion: targetAppVersion,
      message: message ?? _defaultBundleMessage,
      rolloutCohortCount: rolloutCohortCount,
      targetCohorts: targetCohorts,
    );

Bundle _fingerprintBundle({
  required String id,
  required String fingerprintHash,
  bool enabled = true,
  bool shouldForceUpdate = false,
  String channel = 'production',
  String? message,
  int? rolloutCohortCount,
  List<String>? targetCohorts,
}) =>
    Bundle(
      id: id,
      platform: Platform.android,
      shouldForceUpdate: shouldForceUpdate,
      enabled: enabled,
      fileHash: _defaultFileHash,
      storageUri: _defaultStorageUri,
      channel: channel,
      fingerprintHash: fingerprintHash,
      message: message ?? _defaultBundleMessage,
      rolloutCohortCount: rolloutCohortCount,
      targetCohorts: targetCohorts,
    );

AppVersionGetBundlesArgs _appArgs({
  String appVersion = '1.0',
  String bundleId = nilUuid,
  String? minBundleId,
  String channel = 'production',
  String? cohort,
}) =>
    AppVersionGetBundlesArgs(
      platform: Platform.android,
      bundleId: bundleId,
      minBundleId: minBundleId ?? nilUuid,
      channel: channel,
      cohort: cohort,
      appVersion: appVersion,
    );

FingerprintGetBundlesArgs _fpArgs({
  String fingerprintHash = 'hash1',
  String bundleId = nilUuid,
  String? minBundleId,
  String channel = 'production',
  String? cohort,
}) =>
    FingerprintGetBundlesArgs(
      platform: Platform.android,
      bundleId: bundleId,
      minBundleId: minBundleId ?? nilUuid,
      channel: channel,
      cohort: cohort,
      fingerprintHash: fingerprintHash,
    );

// ---------------------------------------------------------------------------
// App version strategy
// ---------------------------------------------------------------------------
void main() {
  group('getUpdateInfo — app version strategy', () {
    test('applies update when a * bundle is available', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '*',
        ),
      ];

      final update = await getUpdateInfo(bundles, _appArgs());

      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.message, 'hello');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('returns null when no bundles are provided', () async {
      final update = await getUpdateInfo([], _appArgs());
      expect(update, isNull);
    });

    test('returns null when app version does not qualify for higher version',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.1',
        ),
      ];

      final update = await getUpdateInfo(bundles, _appArgs());
      expect(update, isNull);
    });

    test('target app version compatibility with available higher version',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '01963024-c131-7971-8725-ab47e232df41',
          targetAppVersion: '1.0.0',
        ),
        _appVersionBundle(
          id: '01963024-c131-7971-8725-ab47e232df42',
          targetAppVersion: '1.0.1',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(bundleId: '01963024-c131-7971-8725-ab47e232df41'),
      );
      expect(update, isNull);
    });

    test('applies update when higher semver-compatible bundle is available',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.x.x',
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000002',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(bundles, _appArgs());
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000002');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
      expect(update.message, 'hello');
    });

    test('applies update when shouldForceUpdate is true', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
          shouldForceUpdate: true,
        ),
      ];

      final update = await getUpdateInfo(bundles, _appArgs());
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.update);
    });

    test('applies update when shouldForceUpdate is false', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
          shouldForceUpdate: false,
        ),
      ];

      final update = await getUpdateInfo(bundles, _appArgs());
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('applies update when bundle is still considered higher', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000005',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(bundles, _appArgs());
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000005');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.message, 'hello');
      expect(update.status, UpdateStatus.update);
    });

    test('falls back to older enabled bundle when latest is disabled', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000002',
          targetAppVersion: '1.0',
          shouldForceUpdate: true,
          enabled: false,
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
          shouldForceUpdate: false,
        ),
      ];

      final update = await getUpdateInfo(bundles, _appArgs());
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('returns null if all bundles are disabled', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000002',
          targetAppVersion: '1.0',
          enabled: false,
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
          enabled: false,
        ),
      ];

      final update = await getUpdateInfo(bundles, _appArgs());
      expect(update, isNull);
    });

    test('rollback if latest bundle is disabled and no other updates enabled',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000002',
          targetAppVersion: '1.0',
          enabled: false,
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
          enabled: false,
        ),
      ];

      final update = await getUpdateInfo(bundles, _appArgs());
      expect(update, isNull);
    });

    test('applies update when same-version bundle is available', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
          message: 'hi',
        ),
      ];

      final update = await getUpdateInfo(bundles, _appArgs());
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
      expect(update.message, 'hi');
    });

    test('forces rollback if no matching bundle exists for provided bundleId',
        () async {
      final update = await getUpdateInfo(
        [],
        _appArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNotNull);
      expect(update!.id, nilUuid);
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
      expect(update.message, isNull);
    });

    test('returns null if user is already up-to-date', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000002',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNull);
    });

    test('rollback if previously used bundle no longer exists', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('selects next available bundle even if shouldForceUpdate is false',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000003',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000002',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000003');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('applies highest available bundle even if app version unchanged',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000005',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000004',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000003',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000002',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000005');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('returns null if newest matching bundle is disabled', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000003',
          targetAppVersion: '1.0',
          enabled: false,
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000002',
          targetAppVersion: '1.0',
          shouldForceUpdate: true,
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNull);
    });

    test('rolls back to older enabled bundle if current is disabled', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000002',
          targetAppVersion: '1.0',
          enabled: false,
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('rollback to init bundle when all bundles are disabled', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000002',
          targetAppVersion: '1.0',
          enabled: false,
        ),
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
          enabled: false,
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNotNull);
      expect(update!.id, nilUuid);
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('returns null when bundle lower than minBundleId', () async {
      final bundles = [
        _appVersionBundle(
          id: '0195715a-ce29-7c55-97d3-53af4fe369b7',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(
          minBundleId: '0195715b-9591-7000-8000-000000000000',
          bundleId: '0195715b-9591-7000-8000-000000000000',
        ),
      );
      expect(update, isNull);
    });

    test('returns bundle when available bundle higher than minBundleId',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '0195715d-42db-7475-9204-31819efc2f1d',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '0195715a-ce29-7c55-97d3-53af4fe369b7',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(
          minBundleId: '0195715b-9591-7000-8000-000000000000',
          bundleId: '0195715b-9591-7000-8000-000000000000',
        ),
      );
      expect(update, isNotNull);
      expect(update!.id, '0195715d-42db-7475-9204-31819efc2f1d');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('rollback when current bundle disabled and only bundles below minBundleId',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '0195715d-42db-7475-9204-31819efc2f1d',
          targetAppVersion: '1.0',
          enabled: false,
        ),
        _appVersionBundle(
          id: '0195715a-ce29-7c55-97d3-53af4fe369b7',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(
          minBundleId: '0195715b-9591-7000-8000-000000000000',
          bundleId: '0195715d-42db-7475-9204-31819efc2f1d',
        ),
      );
      expect(update, isNotNull);
      expect(update!.id, nilUuid);
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('rollback when current bundle does not exist and only below minBundleId',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '0195715a-ce29-7c55-97d3-53af4fe369b7',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(
          minBundleId: '0195715b-9591-7000-8000-000000000000',
          bundleId: '0195715d-42db-7475-9204-31819efc2f1d',
        ),
      );
      expect(update, isNotNull);
      expect(update!.id, nilUuid);
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('returns null when current bundle enabled and no updates available',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '0195715d-42db-7475-9204-31819efc2f1d',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '0195715a-ce29-7c55-97d3-53af4fe369b7',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(
          minBundleId: '0195715b-9591-7000-8000-000000000000',
          bundleId: '0195715d-42db-7475-9204-31819efc2f1d',
        ),
      );
      expect(update, isNull);
    });

    test('rollback when current bundle does not exist and all below minBundleId',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '01957165-bee7-7df3-a25d-6686f01b02ba',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '01957165-19fb-75af-a361-131c17a65ef2',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '01957164-fbc6-785f-98ce-a6ae459f6e4f',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(
          minBundleId: '01957166-6e63-7000-8000-000000000000',
          bundleId: '01957167-0389-7064-8d86-f8af7950daed',
        ),
      );
      expect(update, isNotNull);
      expect(update!.id, nilUuid);
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('rollback to bundle when current does not exist and bundle between minBundleId and bundleId',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '0195716c-82f5-7e5e-ac8c-d4fbf5bc7555',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '01957167-0389-7064-8d86-f8af7950daed',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '01957165-bee7-7df3-a25d-6686f01b02ba',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '01957165-19fb-75af-a361-131c17a65ef2',
          targetAppVersion: '1.0',
        ),
        _appVersionBundle(
          id: '01957164-fbc6-785f-98ce-a6ae459f6e4f',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(
          minBundleId: '01957166-6e63-7000-8000-000000000000',
          bundleId: '0195716c-d426-7308-9924-c3f8cb2eaaad',
        ),
      );
      expect(update, isNotNull);
      expect(update!.id, '0195716c-82f5-7e5e-ac8c-d4fbf5bc7555');
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('returns null when installed bundleId equals minBundleId', () async {
      final bundles = [
        _appVersionBundle(
          id: '01957179-d99d-7fbb-bc1e-feff6b3236f0',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(
          minBundleId: '0195715b-9591-7000-8000-000000000000',
          bundleId: '01957179-d99d-7fbb-bc1e-feff6b3236f0',
        ),
      );
      expect(update, isNull);
    });

    test('does not update bundles from different channels', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
          channel: 'beta',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(channel: 'production'),
      );
      expect(update, isNull);
    });

    test('updates bundles from the same channel', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '1.0',
          channel: 'beta',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(channel: 'beta'),
      );
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.message, 'hello');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('returns null when minBundleId is greater than current bundle', () async {
      final bundles = [
        _appVersionBundle(
          id: '01957b63-7d11-7281-b8e7-1120ccfdb8ab',
          targetAppVersion: '1.0',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(
          bundleId: '01957b63-7d11-7281-b8e7-1120ccfdb8ab',
          minBundleId: '01957bb4-b13c-7000-8000-000000000000',
        ),
      );
      expect(update, isNull);
    });

    test('returns null when no bundles and minBundleId equals bundleId', () async {
      final update = await getUpdateInfo(
        [],
        _appArgs(
          bundleId: '0195d325-767a-7000-8000-000000000000',
          minBundleId: '0195d325-767a-7000-8000-000000000000',
        ),
      );
      expect(update, isNull);
    });

    test('applies update when bundle higher than minBundleId and bundleId equals minBundleId',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '01963024-c131-7971-8725-ab47e232df40',
          targetAppVersion: '1.0.0',
          shouldForceUpdate: true,
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(
          bundleId: '00000000-0000-0000-0000-000000000000',
          minBundleId: '00000000-0000-0000-0000-000000000000',
        ),
      );
      expect(update, isNotNull);
      expect(update!.id, '01963024-c131-7971-8725-ab47e232df40');
      expect(update.message, 'hello');
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.update);
    });

    test('applies update for bounded range >= 5.7.0 <= 5.7.4', () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '>= 5.7.0 <= 5.7.4',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(appVersion: '5.7.3'),
      );
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('returns null for bounded range >= 5.7.0 <= 5.7.4 with version 5.7.5',
        () async {
      final bundles = [
        _appVersionBundle(
          id: '00000000-0000-0000-0000-000000000001',
          targetAppVersion: '>= 5.7.0 <= 5.7.4',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _appArgs(appVersion: '5.7.5'),
      );
      expect(update, isNull);
    });

    test('applies update when many distinct target app versions are compatible',
        () async {
      final bundles = <Bundle>[];
      for (var index = 0; index < 200; index++) {
        final bundleNumber = index + 1;
        bundles.add(
          _appVersionBundle(
            id: '00000000-0000-0000-0000-${bundleNumber.toString().padLeft(12, '0')}',
            targetAppVersion: '>=0.$index.0',
          ),
        );
      }

      final update = await getUpdateInfo(bundles, _appArgs(appVersion: '1.0.0'));
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000200');
      expect(update.message, 'hello');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });
  });

  // ---------------------------------------------------------------------------
  // Fingerprint strategy
  // ---------------------------------------------------------------------------
  group('getUpdateInfo — fingerprint strategy', () {
    test('returns null when no bundles are provided', () async {
      final update = await getUpdateInfo([], _fpArgs());
      expect(update, isNull);
    });

    test('returns null when fingerprint hash does not match', () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000001',
          fingerprintHash: 'hash2',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _fpArgs(fingerprintHash: 'hash1'),
      );
      expect(update, isNull);
    });

    test('fingerprint hash compatibility with available higher version',
        () async {
      final bundles = [
        _fingerprintBundle(
          id: '01963024-c131-7971-8725-ab47e232df41',
          fingerprintHash: 'hash1',
        ),
        _fingerprintBundle(
          id: '01963024-c131-7971-8725-ab47e232df42',
          fingerprintHash: 'hash2',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _fpArgs(bundleId: '01963024-c131-7971-8725-ab47e232df41'),
      );
      expect(update, isNull);
    });

    test('applies update when higher fingerprint-matching bundle available',
        () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000001',
          fingerprintHash: 'hash1',
        ),
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000002',
          fingerprintHash: 'hash2',
        ),
      ];

      final update = await getUpdateInfo(bundles, _fpArgs());
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
      expect(update.message, 'hello');
    });

    test('applies update when shouldForceUpdate is true', () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000001',
          fingerprintHash: 'hash1',
          shouldForceUpdate: true,
        ),
      ];

      final update = await getUpdateInfo(bundles, _fpArgs());
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.update);
    });

    test('applies update when shouldForceUpdate is false', () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000001',
          fingerprintHash: 'hash1',
          shouldForceUpdate: false,
        ),
      ];

      final update = await getUpdateInfo(bundles, _fpArgs());
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('applies update when bundle is still considered higher', () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000005',
          fingerprintHash: 'hash1',
        ),
      ];

      final update = await getUpdateInfo(bundles, _fpArgs());
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000005');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.message, 'hello');
      expect(update.status, UpdateStatus.update);
    });

    test('falls back to older enabled bundle when latest is disabled', () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000002',
          fingerprintHash: 'hash1',
          shouldForceUpdate: true,
          enabled: false,
        ),
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000001',
          fingerprintHash: 'hash1',
          shouldForceUpdate: false,
        ),
      ];

      final update = await getUpdateInfo(bundles, _fpArgs());
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('returns null if all bundles are disabled', () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000002',
          fingerprintHash: 'hash1',
          enabled: false,
        ),
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000001',
          fingerprintHash: 'hash1',
          enabled: false,
        ),
      ];

      final update = await getUpdateInfo(bundles, _fpArgs());
      expect(update, isNull);
    });

    test('rollback if latest bundle is disabled and no other updates enabled',
        () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000002',
          fingerprintHash: 'hash1',
          enabled: false,
        ),
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000001',
          fingerprintHash: 'hash1',
          enabled: false,
        ),
      ];

      final update = await getUpdateInfo(bundles, _fpArgs());
      expect(update, isNull);
    });

    test('applies update when same-fingerprint bundle is available', () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000001',
          fingerprintHash: 'hash1',
          message: 'hi',
        ),
      ];

      final update = await getUpdateInfo(bundles, _fpArgs());
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
      expect(update.message, 'hi');
    });

    test('forces rollback if no matching bundle exists for provided bundleId',
        () async {
      final update = await getUpdateInfo(
        [],
        _appArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNotNull);
      expect(update!.id, nilUuid);
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('returns null if user is already up-to-date', () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000002',
          fingerprintHash: 'hash1',
        ),
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000001',
          fingerprintHash: 'hash1',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _fpArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNull);
    });

    test('rollback if previously used bundle no longer exists', () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000001',
          fingerprintHash: 'hash1',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _fpArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000001');
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('selects next available bundle even if shouldForceUpdate is false',
        () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000003',
          fingerprintHash: 'hash1',
        ),
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000002',
          fingerprintHash: 'hash1',
        ),
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000001',
          fingerprintHash: 'hash1',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _fpArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000003');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('applies highest available bundle even if fingerprint unchanged',
        () async {
      final bundles = [
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000005',
          fingerprintHash: 'hash1',
        ),
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000004',
          fingerprintHash: 'hash1',
        ),
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000003',
          fingerprintHash: 'hash1',
        ),
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000002',
          fingerprintHash: 'hash1',
        ),
        _fingerprintBundle(
          id: '00000000-0000-0000-0000-000000000001',
          fingerprintHash: 'hash1',
        ),
      ];

      final update = await getUpdateInfo(
        bundles,
        _fpArgs(bundleId: '00000000-0000-0000-0000-000000000002'),
      );
      expect(update, isNotNull);
      expect(update!.id, '00000000-0000-0000-0000-000000000005');
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });
  });

  // ---------------------------------------------------------------------------
  // Gradual rollout (app version)
  // ---------------------------------------------------------------------------
  group('getUpdateInfo — gradual rollout (app version)', () {
    test('returns null when rolloutCohortCount is 0', () async {
      final bundle = _appVersionBundle(
        id: '00000000-0000-0000-0000-000000000001',
        targetAppVersion: '1.0',
        rolloutCohortCount: 0,
      );

      final update = await getUpdateInfo(
        [bundle],
        _appArgs(cohort: '1'),
      );
      expect(update, isNull);
    });

    test('applies update when rolloutCohortCount is 1000', () async {
      final bundle = _appVersionBundle(
        id: '00000000-0000-0000-0000-000000000001',
        targetAppVersion: '1.0',
        rolloutCohortCount: 1000,
      );

      final update = await getUpdateInfo(
        [bundle],
        _appArgs(cohort: '1'),
      );
      expect(update, isNotNull);
      expect(update!.id, bundle.id);
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('applies update when rolloutCohortCount is null', () async {
      final bundle = _appVersionBundle(
        id: '00000000-0000-0000-0000-000000000001',
        targetAppVersion: '1.0',
        rolloutCohortCount: null,
      );

      final update = await getUpdateInfo(
        [bundle],
        _appArgs(cohort: '1'),
      );
      expect(update, isNotNull);
      expect(update!.id, bundle.id);
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('excludes custom cohorts from gradual rollout', () async {
      final bundle = _appVersionBundle(
        id: '00000000-0000-0000-0000-000000000001',
        targetAppVersion: '1.0',
        rolloutCohortCount: 1000,
      );

      final update = await getUpdateInfo(
        [bundle],
        _appArgs(cohort: 'qa-group'),
      );
      expect(update, isNull);
    });

    test('applies update when custom cohort is in targetCohorts', () async {
      final bundle = _appVersionBundle(
        id: '00000000-0000-0000-0000-000000000001',
        targetAppVersion: '1.0',
        rolloutCohortCount: 200,
        targetCohorts: ['qa-group'],
      );

      final update = await getUpdateInfo(
        [bundle],
        _appArgs(cohort: 'qa-group'),
      );
      expect(update, isNotNull);
      expect(update!.id, bundle.id);
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('keeps numeric rollout active when targetCohorts are configured',
        () async {
      final bundleId = '00000000-0000-0000-0000-000000000022';
      final eligibleCohort = _findNumericCohort(bundleId, (pos) => pos < 200);

      final bundle = _appVersionBundle(
        id: bundleId,
        targetAppVersion: '1.0',
        rolloutCohortCount: 200,
        targetCohorts: ['qa-group'],
      );

      final update = await getUpdateInfo(
        [bundle],
        _appArgs(cohort: eligibleCohort),
      );
      expect(update, isNotNull);
      expect(update!.id, bundle.id);
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('includes targeted numeric cohorts outside the rollout set', () async {
      final bundleId = '00000000-0000-0000-0000-000000000023';
      final targetedNumericCohort =
          _findNumericCohort(bundleId, (pos) => pos >= 200);

      final bundle = _appVersionBundle(
        id: bundleId,
        targetAppVersion: '1.0',
        rolloutCohortCount: 200,
        targetCohorts: [targetedNumericCohort],
      );

      final update = await getUpdateInfo(
        [bundle],
        _appArgs(cohort: targetedNumericCohort),
      );
      expect(update, isNotNull);
      expect(update!.id, bundle.id);
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('returns latest eligible update when newer bundle targets different cohort',
        () async {
      final eligibleBundleId = '00000000-0000-0000-0000-000000000020';
      final blockedBundleId = '00000000-0000-0000-0000-000000000021';
      final eligibleCohort =
          _findNumericCohort(eligibleBundleId, (pos) => pos < 200);

      final update = await getUpdateInfo(
        [
          _appVersionBundle(
            id: eligibleBundleId,
            targetAppVersion: '1.0',
            rolloutCohortCount: 200,
          ),
          _appVersionBundle(
            id: blockedBundleId,
            targetAppVersion: '1.0',
            rolloutCohortCount: 0,
            targetCohorts: ['qa-group'],
          ),
        ],
        _appArgs(cohort: eligibleCohort),
      );
      expect(update, isNotNull);
      expect(update!.id, eligibleBundleId);
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('re-evaluates current bundle eligibility and rolls back',
        () async {
      final previousBundleId = '00000000-0000-0000-0000-000000000020';
      final currentBundleId = '00000000-0000-0000-0000-000000000021';

      final update = await getUpdateInfo(
        [
          _appVersionBundle(
            id: previousBundleId,
            targetAppVersion: '1.0',
            rolloutCohortCount: 1000,
          ),
          _appVersionBundle(
            id: currentBundleId,
            targetAppVersion: '1.0',
            rolloutCohortCount: 0,
            targetCohorts: ['qa-group'],
          ),
        ],
        _appArgs(
          bundleId: currentBundleId,
          cohort: '1',
        ),
      );
      expect(update, isNotNull);
      expect(update!.id, previousBundleId);
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('re-evaluates eligibility and falls back to init bundle', () async {
      final currentBundleId = '00000000-0000-0000-0000-000000000021';

      final update = await getUpdateInfo(
        [
          _appVersionBundle(
            id: currentBundleId,
            targetAppVersion: '1.0',
            rolloutCohortCount: 0,
            targetCohorts: ['qa-group'],
          ),
        ],
        _appArgs(
          bundleId: currentBundleId,
          cohort: '1',
        ),
      );
      expect(update, isNotNull);
      expect(update!.id, nilUuid);
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('applies ROLLBACK regardless of rollout settings', () async {
      final bundle = _appVersionBundle(
        id: '00000000-0000-0000-0000-000000000001',
        targetAppVersion: '1.0',
        rolloutCohortCount: 0,
        targetCohorts: ['qa-group'],
      );

      final update = await getUpdateInfo(
        [bundle],
        _appArgs(
          bundleId: '00000000-0000-0000-0000-000000000002',
          cohort: 'not-targeted',
        ),
      );
      expect(update, isNotNull);
      expect(update!.id, bundle.id);
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });
  });

  // ---------------------------------------------------------------------------
  // Gradual rollout (fingerprint)
  // ---------------------------------------------------------------------------
  group('getUpdateInfo — gradual rollout (fingerprint)', () {
    test('returns null when rolloutCohortCount is 0', () async {
      final bundle = _fingerprintBundle(
        id: '00000000-0000-0000-0000-000000000001',
        fingerprintHash: 'hash1',
        rolloutCohortCount: 0,
      );

      final update = await getUpdateInfo(
        [bundle],
        _fpArgs(cohort: '1'),
      );
      expect(update, isNull);
    });

    test('applies update when rolloutCohortCount is 1000', () async {
      final bundle = _fingerprintBundle(
        id: '00000000-0000-0000-0000-000000000001',
        fingerprintHash: 'hash1',
        rolloutCohortCount: 1000,
      );

      final update = await getUpdateInfo(
        [bundle],
        _fpArgs(cohort: '1'),
      );
      expect(update, isNotNull);
      expect(update!.id, bundle.id);
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('applies update when rolloutCohortCount is null', () async {
      final bundle = _fingerprintBundle(
        id: '00000000-0000-0000-0000-000000000001',
        fingerprintHash: 'hash1',
        rolloutCohortCount: null,
      );

      final update = await getUpdateInfo(
        [bundle],
        _fpArgs(cohort: '1'),
      );
      expect(update, isNotNull);
      expect(update!.id, bundle.id);
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('excludes custom cohorts from gradual rollout', () async {
      final bundle = _fingerprintBundle(
        id: '00000000-0000-0000-0000-000000000001',
        fingerprintHash: 'hash1',
        rolloutCohortCount: 1000,
      );

      final update = await getUpdateInfo(
        [bundle],
        _fpArgs(cohort: 'qa-group'),
      );
      expect(update, isNull);
    });

    test('applies update when custom cohort is in targetCohorts', () async {
      final bundle = _fingerprintBundle(
        id: '00000000-0000-0000-0000-000000000001',
        fingerprintHash: 'hash1',
        rolloutCohortCount: 200,
        targetCohorts: ['qa-group'],
      );

      final update = await getUpdateInfo(
        [bundle],
        _fpArgs(cohort: 'qa-group'),
      );
      expect(update, isNotNull);
      expect(update!.id, bundle.id);
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('keeps numeric rollout active when targetCohorts are configured',
        () async {
      final bundleId = '00000000-0000-0000-0000-000000000022';
      final eligibleCohort = _findNumericCohort(bundleId, (pos) => pos < 200);

      final bundle = _fingerprintBundle(
        id: bundleId,
        fingerprintHash: 'hash1',
        rolloutCohortCount: 200,
        targetCohorts: ['qa-group'],
      );

      final update = await getUpdateInfo(
        [bundle],
        _fpArgs(cohort: eligibleCohort),
      );
      expect(update, isNotNull);
      expect(update!.id, bundle.id);
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('includes targeted numeric cohorts outside the rollout set', () async {
      final bundleId = '00000000-0000-0000-0000-000000000023';
      final targetedNumericCohort =
          _findNumericCohort(bundleId, (pos) => pos >= 200);

      final bundle = _fingerprintBundle(
        id: bundleId,
        fingerprintHash: 'hash1',
        rolloutCohortCount: 200,
        targetCohorts: [targetedNumericCohort],
      );

      final update = await getUpdateInfo(
        [bundle],
        _fpArgs(cohort: targetedNumericCohort),
      );
      expect(update, isNotNull);
      expect(update!.id, bundle.id);
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('returns latest eligible update when newer bundle targets different cohort',
        () async {
      final eligibleBundleId = '00000000-0000-0000-0000-000000000020';
      final blockedBundleId = '00000000-0000-0000-0000-000000000021';
      final eligibleCohort =
          _findNumericCohort(eligibleBundleId, (pos) => pos < 200);

      final update = await getUpdateInfo(
        [
          _fingerprintBundle(
            id: eligibleBundleId,
            fingerprintHash: 'hash1',
            rolloutCohortCount: 200,
          ),
          _fingerprintBundle(
            id: blockedBundleId,
            fingerprintHash: 'hash1',
            rolloutCohortCount: 0,
            targetCohorts: ['qa-group'],
          ),
        ],
        _fpArgs(cohort: eligibleCohort),
      );
      expect(update, isNotNull);
      expect(update!.id, eligibleBundleId);
      expect(update.shouldForceUpdate, isFalse);
      expect(update.status, UpdateStatus.update);
    });

    test('re-evaluates current bundle eligibility and rolls back', () async {
      final previousBundleId = '00000000-0000-0000-0000-000000000020';
      final currentBundleId = '00000000-0000-0000-0000-000000000021';

      final update = await getUpdateInfo(
        [
          _fingerprintBundle(
            id: previousBundleId,
            fingerprintHash: 'hash1',
            rolloutCohortCount: 1000,
          ),
          _fingerprintBundle(
            id: currentBundleId,
            fingerprintHash: 'hash1',
            rolloutCohortCount: 0,
            targetCohorts: ['qa-group'],
          ),
        ],
        _fpArgs(
          bundleId: currentBundleId,
          cohort: '1',
        ),
      );
      expect(update, isNotNull);
      expect(update!.id, previousBundleId);
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('re-evaluates eligibility and falls back to init bundle', () async {
      final currentBundleId = '00000000-0000-0000-0000-000000000021';

      final update = await getUpdateInfo(
        [
          _fingerprintBundle(
            id: currentBundleId,
            fingerprintHash: 'hash1',
            rolloutCohortCount: 0,
            targetCohorts: ['qa-group'],
          ),
        ],
        _fpArgs(
          bundleId: currentBundleId,
          cohort: '1',
        ),
      );
      expect(update, isNotNull);
      expect(update!.id, nilUuid);
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });

    test('applies ROLLBACK regardless of rollout settings', () async {
      final bundle = _fingerprintBundle(
        id: '00000000-0000-0000-0000-000000000001',
        fingerprintHash: 'hash1',
        rolloutCohortCount: 0,
        targetCohorts: ['qa-group'],
      );

      final update = await getUpdateInfo(
        [bundle],
        _fpArgs(
          bundleId: '00000000-0000-0000-0000-000000000002',
          cohort: 'not-targeted',
        ),
      );
      expect(update, isNotNull);
      expect(update!.id, bundle.id);
      expect(update.shouldForceUpdate, isTrue);
      expect(update.status, UpdateStatus.rollback);
    });
  });
}

String _findNumericCohort(
  String bundleId,
  bool Function(int position) predicate,
) {
  for (var cohort = 1; cohort <= numericCohortSize; cohort++) {
    if (predicate(getNumericCohortRolloutPosition(bundleId, cohort))) {
      return '$cohort';
    }
  }
  throw StateError('No numeric cohort matched for bundle $bundleId');
}
