import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show
        AppVersionGetBundlesArgs,
        Bundle,
        FingerprintGetBundlesArgs,
        Platform,
        UpdateInfo,
        UpdateStatus,
        nilUuid;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show DatabaseBundleQueryOptions, DatabaseBundleQueryWhere, Paginated;
import 'package:test/test.dart';

import 'mock_postgres_client.dart';

Bundle _bundle(
  String id, {
  String channel = 'production',
  String? fingerprintHash,
}) => Bundle(
  id: id,
  platform: Platform.android,
  shouldForceUpdate: false,
  enabled: true,
  fileHash: 'file-hash-$id',
  channel: channel,
  storageUri: 'file:///bundle-$id',
  targetAppVersion: '1.0.0',
  message: null,
  fingerprintHash: fingerprintHash,
  metadata: null,
  manifestStorageUri: null,
  manifestFileHash: null,
  assetBaseStorageUri: null,
  patches: const [],
  patchBaseBundleId: null,
  patchBaseFileHash: null,
  patchFileHash: null,
  patchStorageUri: null,
  rolloutCohortCount: 1000,
  targetCohorts: null,
);

void main() {
  group('postgresDatabase', () {
    test('getChannels returns distinct channels', () async {
      final plugin = newPlugin();
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000001'),
      );
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000002', channel: 'staging'),
      );
      await plugin.commitBundle();

      final channels = await plugin.getChannels();
      expect(channels, containsAll(['production', 'staging']));
      expect(channels.length, 2);
    });

    test('getBundles returns bundles and pagination', () async {
      final plugin = newPlugin();
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000001'),
      );
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000002'),
      );
      await plugin.commitBundle();

      final result = await plugin.getBundles(
        const DatabaseBundleQueryOptions(limit: 10),
      );
      expect(result, isA<Paginated<List<Bundle>>>());
      expect(result.data, hasLength(2));
      expect(result.pagination.total, 2);
    });

    test('getBundles filters by channel', () async {
      final plugin = newPlugin();
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000001'),
      );
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000002', channel: 'staging'),
      );
      await plugin.commitBundle();

      final result = await plugin.getBundles(
        DatabaseBundleQueryOptions(
          where: const DatabaseBundleQueryWhere(channel: 'staging'),
          limit: 10,
        ),
      );
      expect(result.data, hasLength(1));
      expect(result.data.first.channel, 'staging');
    });

    test(
      'getBundleById returns null for missing, bundle for existing',
      () async {
        final plugin = newPlugin();
        await plugin.appendBundle(
          _bundle('018f0000-0000-7000-8000-000000000001'),
        );
        await plugin.commitBundle();

        expect(await plugin.getBundleById('does-not-exist'), isNull);
        final got = await plugin.getBundleById(
          '018f0000-0000-7000-8000-000000000001',
        );
        expect(got, isNotNull);
        expect(got!.id, '018f0000-0000-7000-8000-000000000001');
      },
    );

    test('commitBundle append -> update -> delete reflects in store', () async {
      final plugin = newPlugin();
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000001'),
      );
      await plugin.commitBundle();

      var got = await plugin.getBundleById(
        '018f0000-0000-7000-8000-000000000001',
      );
      expect(got!.enabled, true);

      await plugin.updateBundle(got.id, {'enabled': false});
      await plugin.commitBundle();
      got = await plugin.getBundleById('018f0000-0000-7000-8000-000000000001');
      expect(got!.enabled, false);

      await plugin.deleteBundle(got);
      await plugin.commitBundle();
      expect(
        await plugin.getBundleById('018f0000-0000-7000-8000-000000000001'),
        isNull,
      );
    });

    test(
      'getUpdateInfo via RPC returns UpdateInfo for compatible bundle',
      () async {
        final plugin = newPlugin();
        await plugin.appendBundle(
          _bundle('018f0000-0000-7000-8000-000000000001'),
        );
        await plugin.commitBundle();

        final info = await plugin.getUpdateInfo(
          AppVersionGetBundlesArgs(
            appVersion: '1.0.0',
            bundleId: nilUuid,
            channel: 'production',
            minBundleId: nilUuid,
            platform: Platform.android,
          ),
        );
        expect(info, isA<UpdateInfo>());
        expect(info!.status, UpdateStatus.update);
        expect(
          info.storageUri,
          'file:///bundle-018f0000-0000-7000-8000-000000000001',
        );
      },
    );

    test('getUpdateInfo via fingerprint returns matching bundle', () async {
      final plugin = newPlugin();
      final fpBundle = _bundle(
        '018f0000-0000-7000-8000-000000000001',
        fingerprintHash: 'fp-abc',
      );
      await plugin.appendBundle(fpBundle);
      await plugin.commitBundle();

      final info = await plugin.getUpdateInfo(
        FingerprintGetBundlesArgs(
          fingerprintHash: 'fp-abc',
          bundleId: nilUuid,
          channel: 'production',
          minBundleId: nilUuid,
          platform: Platform.android,
        ),
      );
      expect(info, isA<UpdateInfo>());
      expect(info!.fileHash, 'file-hash-018f0000-0000-7000-8000-000000000001');
    });

    test('getUpdateInfo returns null when no compatible bundle', () async {
      final plugin = newPlugin();
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000001'),
      );
      await plugin.commitBundle();

      final info = await plugin.getUpdateInfo(
        AppVersionGetBundlesArgs(
          appVersion: '9.9.9',
          bundleId: nilUuid,
          channel: 'production',
          minBundleId: nilUuid,
          platform: Platform.android,
        ),
      );
      expect(info, isNull);
    });
  });
}
