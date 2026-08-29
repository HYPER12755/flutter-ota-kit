import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show
        AppVersionGetBundlesArgs,
        Bundle,
        BundlePatchArtifact,
        FingerprintGetBundlesArgs,
        Platform,
        UpdateStatus,
        nilUuid;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show DatabasePlugin;
import 'package:test/test.dart';

import 'mock_d1_client.dart' show Store, newWorkerPlugin;

Bundle _makeBundle({
  required String id,
  String channel = 'production',
  bool enabled = true,
  String? fingerprintHash,
  String? targetAppVersion,
  String? message,
  List<BundlePatchArtifact>? patches,
}) =>
    Bundle(
      id: id,
      channel: channel,
      enabled: enabled,
      shouldForceUpdate: false,
      fileHash: 'h-$id',
      platform: Platform.android,
      targetAppVersion: targetAppVersion,
      storageUri: 's3://$id',
      fingerprintHash: fingerprintHash,
      message: message,
      patches: patches,
    );

void main() {
  group('cloudflare d1WorkerDatabase', () {
    late Store store;
    late DatabasePlugin plugin;

    setUp(() {
      store = Store();
      plugin = newWorkerPlugin(store);
    });

    test('getChannels returns distinct channels', () async {
      await plugin.appendBundle(_makeBundle(id: 'a', channel: 'production'));
      await plugin.appendBundle(_makeBundle(id: 'b', channel: 'staging'));
      await plugin.appendBundle(_makeBundle(id: 'c', channel: 'production'));
      await plugin.commitBundle();

      final channels = await plugin.getChannels();
      expect(channels, hasLength(2));
      expect(channels, containsAll(['production', 'staging']));
    });

    test('getBundleById returns null for missing, bundle for existing',
        () async {
      await plugin.appendBundle(_makeBundle(id: 'b1'));
      await plugin.commitBundle();

      expect(await plugin.getBundleById('missing'), isNull);
      final got = await plugin.getBundleById('b1');
      expect(got, isNotNull);
      expect(got!.id, 'b1');
    });

    test('commitBundle append -> update -> delete reflects in store',
        () async {
      await plugin.appendBundle(_makeBundle(id: 'b1', message: 'original'));
      await plugin.commitBundle();
      expect((await plugin.getBundleById('b1'))!.message, 'original');

      var got = await plugin.getBundleById('b1');
      await plugin.updateBundle(got!.id, {'message': 'updated'});
      await plugin.commitBundle();
      expect((await plugin.getBundleById('b1'))!.message, 'updated');

      got = await plugin.getBundleById('b1');
      await plugin.deleteBundle(got!);
      await plugin.commitBundle();
      expect(await plugin.getBundleById('b1'), isNull);
    });

    test('getUpdateInfo (appVersion) returns UpdateInfo for compatible bundle',
        () async {
      await plugin.appendBundle(_makeBundle(id: 'b1', targetAppVersion: '1.0.0'));
      await plugin.commitBundle();

      final info = await plugin.getUpdateInfo(
        AppVersionGetBundlesArgs(
          platform: Platform.android,
          bundleId: nilUuid,
          appVersion: '1.0.0',
          channel: 'production',
          minBundleId: nilUuid,
        ),
      );
      expect(info, isNotNull);
      expect(info!.id, 'b1');
      expect(info.status, UpdateStatus.update);
    });

    test('getUpdateInfo (fingerprint) returns matching bundle', () async {
      await plugin.appendBundle(_makeBundle(id: 'fp', fingerprintHash: 'fp1'));
      await plugin.commitBundle();

      final info = await plugin.getUpdateInfo(
        FingerprintGetBundlesArgs(
          platform: Platform.android,
          bundleId: nilUuid,
          fingerprintHash: 'fp1',
        ),
      );
      expect(info, isNotNull);
      expect(info!.id, 'fp');
    });
  });
}
