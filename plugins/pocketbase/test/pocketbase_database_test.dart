import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show
        AppVersionGetBundlesArgs,
        Bundle,
        FingerprintGetBundlesArgs,
        Platform,
        UpdateStatus,
        nilUuid;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show DatabaseBundleQueryOptions, DatabaseBundleQueryWhere;
import 'package:flutter_ota_kit_pocketbase/flutter_ota_kit_pocketbase.dart';
import 'package:test/test.dart';

import 'fake_pocketbase_client.dart';

Bundle _bundle(
  String id, {
  String channel = 'production',
  String appVersion = '1.0.0',
  String? fingerprintHash,
  bool enabled = true,
  bool force = false,
}) => Bundle(
  id: id,
  platform: Platform.android,
  shouldForceUpdate: force,
  enabled: enabled,
  fileHash: 'hash-$id',
  channel: channel,
  storageUri: 'pb://bundles/$id/patch.zip',
  targetAppVersion: fingerprintHash == null ? appVersion : null,
  message: 'msg-$id',
  fingerprintHash: fingerprintHash,
  metadata: null,
  manifestStorageUri: null,
  manifestFileHash: null,
  assetBaseStorageUri: null,
  patches: const [],
  rolloutCohortCount: 1000,
  targetCohorts: null,
);

/// Build the plugin over a shared in-memory fake client so both the plugin and
/// the test can inspect the same store.
({dynamic plugin, PbStore store}) _newPlugin() {
  final store = PbStore();
  final config = PocketBaseConfig(
    url: 'http://fake',
    adminEmail: 'admin@test.dev',
    adminPassword: 'password123',
    clientFactory: (_, __, ___) => FakePocketBaseClient(store),
  );
  return (plugin: pocketbaseDatabase(config)(), store: store);
}

void main() {
  group('pocketbaseDatabase', () {
    test('append + getBundleById round-trips', () async {
      final (:plugin, :store) = _newPlugin();
      await plugin.appendBundle(_bundle('018f0000-0000-7000-8000-000000000001'));
      await plugin.commitBundle();

      final got = await plugin.getBundleById(
        '018f0000-0000-7000-8000-000000000001',
      );
      expect(got, isNotNull);
      expect(got!.channel, 'production');
      expect(got.platform, Platform.android);
      expect(got.storageUri, 'pb://bundles/018f0000-0000-7000-8000-000000000001/patch.zip');
    });

    test('getChannels derives distinct channels from bundles', () async {
      final (:plugin, :store) = _newPlugin();
      await plugin.appendBundle(_bundle('018f0000-0000-7000-8000-000000000001'));
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000002', channel: 'staging'),
      );
      await plugin.commitBundle();

      final channels = await plugin.getChannels();
      // This is the regression guard: previously getChannels returned the empty
      // `channels` collection and never fell through to bundle-derived names.
      expect(channels, containsAll(['production', 'staging']));
      expect(channels.length, 2);
    });

    test('getBundles filters by channel + enabled and paginates', () async {
      final (:plugin, :store) = _newPlugin();
      await plugin.appendBundle(_bundle('018f0000-0000-7000-8000-000000000001'));
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000002', enabled: false),
      );
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000003', channel: 'staging'),
      );
      await plugin.commitBundle();

      final prod = await plugin.getBundles(
        const DatabaseBundleQueryOptions(
          where: DatabaseBundleQueryWhere(channel: 'production', enabled: true),
          limit: 10,
        ),
      );
      expect(prod.data.length, 1);
      expect(prod.data.single.id, '018f0000-0000-7000-8000-000000000001');
      expect(prod.pagination.total, 1);
    });

    test('getUpdateInfo (appVersion) returns the newest compatible bundle',
        () async {
      final (:plugin, :store) = _newPlugin();
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000001', appVersion: '1.0.0'),
      );
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000002', appVersion: '1.0.0'),
      );
      await plugin.commitBundle();

      final info = await plugin.getUpdateInfo(
        const AppVersionGetBundlesArgs(
          channel: 'production',
          platform: Platform.android,
          bundleId: nilUuid,
          minBundleId: nilUuid,
          appVersion: '1.0.0',
        ),
      );
      expect(info, isNotNull);
      expect(info!.status, UpdateStatus.update);
      // Newest (highest id) wins.
      expect(info.id, '018f0000-0000-7000-8000-000000000002');
      expect(info.storageUri, isNotNull);
    });

    test('getUpdateInfo (appVersion) returns null when nothing compatible',
        () async {
      final (:plugin, :store) = _newPlugin();
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000001', appVersion: '2.0.0'),
      );
      await plugin.commitBundle();

      final info = await plugin.getUpdateInfo(
        const AppVersionGetBundlesArgs(
          channel: 'production',
          platform: Platform.android,
          bundleId: nilUuid,
          minBundleId: nilUuid,
          appVersion: '1.0.0',
        ),
      );
      expect(info, isNull);
    });

    test('getUpdateInfo (fingerprint) matches by fingerprint hash', () async {
      final (:plugin, :store) = _newPlugin();
      await plugin.appendBundle(
        _bundle(
          '018f0000-0000-7000-8000-000000000001',
          fingerprintHash: 'fp-abc',
        ),
      );
      await plugin.commitBundle();

      final hit = await plugin.getUpdateInfo(
        const FingerprintGetBundlesArgs(
          channel: 'production',
          platform: Platform.android,
          bundleId: nilUuid,
          minBundleId: nilUuid,
          fingerprintHash: 'fp-abc',
        ),
      );
      expect(hit, isNotNull);
      expect(hit!.id, '018f0000-0000-7000-8000-000000000001');

      final miss = await plugin.getUpdateInfo(
        const FingerprintGetBundlesArgs(
          channel: 'production',
          platform: Platform.android,
          bundleId: nilUuid,
          minBundleId: nilUuid,
          fingerprintHash: 'fp-other',
        ),
      );
      expect(miss, isNull);
    });

    test('updateBundle + deleteBundle mutate through commit', () async {
      final (:plugin, :store) = _newPlugin();
      await plugin.appendBundle(_bundle('018f0000-0000-7000-8000-000000000001'));
      await plugin.commitBundle();

      await plugin.updateBundle('018f0000-0000-7000-8000-000000000001', {
        'enabled': false,
      });
      await plugin.commitBundle();
      final disabled = await plugin.getBundleById(
        '018f0000-0000-7000-8000-000000000001',
      );
      expect(disabled!.enabled, isFalse);

      final existing = await plugin.getBundleById(
        '018f0000-0000-7000-8000-000000000001',
      );
      await plugin.deleteBundle(existing!);
      await plugin.commitBundle();
      final gone = await plugin.getBundleById(
        '018f0000-0000-7000-8000-000000000001',
      );
      expect(gone, isNull);
    });
  });
}
