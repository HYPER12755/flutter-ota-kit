import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
import 'package:test/test.dart';

Bundle _sample() => Bundle(
  id: '019b76da-a800-7cc2-b5a5-c8f4a1e9d001',
  platform: Platform.android,
  shouldForceUpdate: false,
  enabled: true,
  fileHash: 'a' * 64,
  storageUri: 'supabase-storage://flutter-ota-storage/bundles/x/bundle.zip',
  gitCommitHash: 'deadbeef',
  message: 'test bundle',
  channel: 'production',
  targetAppVersion: '^1.2.0',
  metadata: const BundleMetadata(appVersion: '1.2.3'),
  rolloutCohortCount: 137,
  targetCohorts: ['qa-group'],
  patches: [
    BundlePatchArtifact(
      baseBundleId: 'base-id',
      baseFileHash: 'b' * 64,
      patchFileHash: 'c' * 64,
      patchStorageUri: 'supabase-storage://bucket/patches/p.bsdiff',
    ),
  ],
);

void main() {
  group('Bundle JSON', () {
    test('camelCase roundtrip preserves all fields', () {
      final b = _sample();
      final parsed = Bundle.fromJson(b.toJson());
      expect(parsed.id, b.id);
      expect(parsed.platform, Platform.android);
      expect(parsed.channel, 'production');
      expect(parsed.targetAppVersion, '^1.2.0');
      expect(parsed.metadata?.appVersion, '1.2.3');
      expect(parsed.rolloutCohortCount, 137);
      expect(parsed.targetCohorts, ['qa-group']);
      expect(parsed.patches?.single, b.patches!.single);
    });

    test('snake_case DB row parses (PostgREST shape)', () {
      final row = _sample().toSqlJson();
      final parsed = Bundle.fromJson(row.cast<String, dynamic>());
      expect(parsed.id, _sample().id);
      expect(parsed.shouldForceUpdate, isFalse);
      expect(parsed.patches?.single.baseBundleId, 'base-id');
      expect(parsed.rolloutCohortCount, 137);
    });

    test('defaults applied on sparse json', () {
      final parsed = Bundle.fromJson({
        'id': 'x',
        'platform': 'android',
        'file_hash': 'h',
        'storage_uri': 's://u',
      });
      expect(parsed.channel, 'production');
      expect(parsed.enabled, isFalse);
      expect(parsed.shouldForceUpdate, isFalse);
      expect(parsed.message, isNull);
    });

    test('sql row carries constraint-relevant fields', () {
      final sql = _sample().toSqlJson();
      expect(sql.containsKey('target_app_version'), isTrue);
      expect(sql['metadata'], isA<Map>());
      // XOR constraint mirrors DB CHECK:
      final hasFingerprint = sql['fingerprint_hash'] != null;
      final hasVersion = sql['target_app_version'] != null;
      expect(hasFingerprint || hasVersion, isTrue);
    });

    test('equality by wire fields', () {
      expect(_sample(), equals(_sample()));
    });
  });

  group('AppUpdateInfo union', () {
    test('parses UP_TO_DATE', () {
      final info = AppUpdateInfo.fromJson({'status': 'UP_TO_DATE'});
      expect(info, isA<AppUpToDateInfo>());
    });

    test('parses UPDATE with changed assets', () {
      final info = AppUpdateInfo.fromJson({
        'id': 'new-id',
        'shouldForceUpdate': true,
        'message': null,
        'status': 'UPDATE',
        'fileUrl': 'https://cdn/b.zip',
        'fileHash': 'd' * 64,
        'changedAssets': {
          'assets/logo.png': {
            'fileHash': 'e' * 64,
            'file': {'url': 'https://cdn/logo.png', 'compression': null},
            'patch': null,
          },
        },
      }) as AppUpdateAvailableInfo;
      expect(info.status, UpdateStatus.update);
      expect(
        info.changedAssets?['assets/logo.png']?.file?.url,
        'https://cdn/logo.png',
      );
    });

    test('available info serializes', () {
      const info = AppUpdateAvailableInfo(
        id: 'i',
        shouldForceUpdate: true,
        message: null,
        status: UpdateStatus.rollback,
        fileUrl: null,
        fileHash: null,
      );
      expect(info.toJson()['status'], 'ROLLBACK');
    });
  });

  group('enums', () {
    test('values match hot-updater strings', () {
      expect(Platform.ios.value, 'ios');
      expect(Platform.android.value, 'android');
      expect(AppUpdateStatus.upToDate.value, 'UP_TO_DATE');
      expect(UpdateStrategy.fingerprint.value, 'fingerprint');
      expect(() => Platform.fromValue('windows'), throwsArgumentError);
    });
  });
}
