import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ota_kit/src/pkg/core/flutter_ota_kit_core.dart'
    show
        AppUpdateStatus,
        Bundle,
        GetBundlesArgs,
        getDefaultNumericCohort,
        nilUuid,
        Platform,
        UpdateInfo,
        UpdateStatus,
        UpdateStrategy;
import 'package:flutter_ota_kit/src/pkg/client/flutter_ota_kit_client.dart'
    show ServerUpdateResult;
import 'package:flutter_ota_kit/src/pkg/plugin_core/flutter_ota_kit_plugin_core.dart'
    show
        DatabaseBundleQueryOptions,
        DatabasePlugin,
        Paginated,
        PaginationInfo,
        RuntimeStorageProfile,
        StoragePlugin,
        StoragePluginProfiles;
import 'package:flutter_ota_kit/src/shared_update_check.dart';

/// Database fake recording the args it was queried with, returning a canned
/// [UpdateInfo].
class _RecordingDatabase implements DatabasePlugin {
  _RecordingDatabase(this.result);

  final UpdateInfo? result;
  GetBundlesArgs? capturedArgs;

  @override
  String get name => 'recordingDatabase';

  @override
  Future<Bundle?> getBundleById(String bundleId) async => null;

  @override
  Future<List<String>> getChannels() async => const ['production'];

  @override
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args) async {
    capturedArgs = args;
    return result;
  }

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) async => Paginated(
    data: const <Bundle>[],
    pagination: PaginationInfo(
      total: 0,
      hasNextPage: false,
      hasPreviousPage: false,
      currentPage: 1,
      totalPages: 0,
    ),
  );

  @override
  Future<void> updateBundle(String id, Map<String, Object?> patch) async {}

  @override
  Future<void> appendBundle(Bundle b) async {}

  @override
  Future<void> commitBundle() async {}

  @override
  Future<void> deleteBundle(Bundle b) async {}

  @override
  Future<void> onUnmount() async {}
}

class _NoopStorage implements StoragePlugin {
  @override
  String get name => 'noopStorage';

  @override
  String get supportedProtocol => 'mock:';

  @override
  StoragePluginProfiles get profiles => const StoragePluginProfiles();
}

class _FakeRuntime implements RuntimeStorageProfile {
  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async => const {
    'fileUrl': 'https://example.invalid/patch.zip',
  };

  @override
  Future<String?> readText(String storageUri) async => null;
}

class _UrlStorage implements StoragePlugin {
  @override
  String get name => 'urlStorage';

  @override
  String get supportedProtocol => 'https:';

  @override
  StoragePluginProfiles get profiles =>
      StoragePluginProfiles(runtime: _FakeRuntime());
}

const _channel = MethodChannel('flutter_ota_kit');

UpdateInfo _row({
  String id = '01a0e51b-cab1-7cc6-929a-47ea95ef2c43',
  UpdateStatus status = UpdateStatus.update,
  String? storageUri = 'supabase-storage://bundles/x/patch.zip',
}) => UpdateInfo(
  id: id,
  shouldForceUpdate: false,
  message: 'msg',
  status: status,
  storageUri: storageUri,
  fileHash: 'md5hash',
);

Future<ServerUpdateResult> _check({
  required _RecordingDatabase db,
  String? cohort,
  StoragePlugin? storage,
}) => performSharedUpdateCheck(
  db: db,
  storage: storage ?? _NoopStorage(),
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
  appVersion: '1.0.0',
  fingerprintHash: null,
  minBundleId: nilUuid,
  cohort: cohort,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cohort threading (config.cohort was dead code)', () {
    test('an explicit config cohort reaches the database args', () async {
      final db = _RecordingDatabase(null);
      await _check(db: db, cohort: 'qa-group');
      expect(db.capturedArgs?.cohort, 'qa-group');
    });

    test('with no cohort and no native deviceId, cohort stays null', () async {
      // flutter_test's default messenger throws MissingPluginException for
      // unmocked channels — exactly what old base APKs do. Must degrade to
      // the historical null behaviour, not crash the check.
      final db = _RecordingDatabase(null);
      final result = await _check(db: db);
      expect(db.capturedArgs?.cohort, isNull);
      expect(result.isUpToDate, isTrue);
    });

    test('with a native deviceId the cohort is derived from it', () async {
      const deviceId = 'device-abc-123';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'deviceId') return deviceId;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null),
      );

      final db = _RecordingDatabase(null);
      await _check(db: db);
      expect(db.capturedArgs?.cohort, getDefaultNumericCohort(deviceId));
      expect(db.capturedArgs?.cohort, '809'); // ground truth from rollout_test
    });
  });

  group('rollback response handling', () {
    test(
      'a ROLLBACK UpdateInfo becomes AppUpdateStatus.rollback '
      "(was dead code: the enum was compared to the string 'ROLLBACK')",
      () async {
        final db = _RecordingDatabase(
          _row(status: UpdateStatus.rollback, storageUri: null),
        );
        final result = await _check(db: db);

        expect(result.status, AppUpdateStatus.rollback);
        expect(result.isUpToDate, isFalse);
        expect(result.patch, isNull);
      },
    );

    test('a rollback row keeps its bundle id and message', () async {
      const oldId = '01a0e51b-cab1-7cc6-929a-47ea95ef2c43';
      final db = _RecordingDatabase(
        _row(id: oldId, status: UpdateStatus.rollback, storageUri: null),
      );
      final result = await _check(db: db);

      expect(result.id, oldId);
      expect(result.message, 'msg');
    });
  });

  group('device identity contract', () {
    test('the applied patch carries the SERVER BUNDLE UUID as its version — '
        'this is what currentVersion() echoes back, making rollback '
        'addressable', () async {
      const bundleUuid = '01a0e810-53ea-7a0e-bf23-b25dc0230ce3';
      final db = _RecordingDatabase(_row(id: bundleUuid));
      final result = await _check(db: db, storage: _UrlStorage());

      expect(result.patch?.version, bundleUuid);
      expect(result.id, bundleUuid);
    });
  });
}
