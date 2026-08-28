import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show
        AppVersionGetBundlesArgs,
        Bundle,
        BundlePatchArtifact,
        FingerprintGetBundlesArgs,
        Platform,
        UpdateStatus,
        nilUuid;
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show
        DatabaseBundleQueryOptions,
        DatabaseBundleQueryOrder,
        DatabaseBundleQueryWhere,
        DatabasePlugin;
import 'package:test/test.dart';

import 'mock_d1_client.dart' show Store, newPlugin;

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
  group('cloudflare d1Database', () {
    late Store store;
    late DatabasePlugin plugin;

    setUp(() {
      store = Store();
      plugin = newPlugin(store);
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

    test('getBundles returns bundles and pagination; filters by channel',
        () async {
      for (final id in ['b1', 'b2', 'b3']) {
        await plugin.appendBundle(_makeBundle(id: id));
      }
      await plugin.commitBundle();

      final res = await plugin.getBundles(
        DatabaseBundleQueryOptions(
          where: const DatabaseBundleQueryWhere(),
          limit: 2,
          offset: 0,
          orderBy: const DatabaseBundleQueryOrder(direction: 'desc'),
        ),
      );
      expect(res.data, hasLength(2));
      expect(res.pagination.total, 3);
      expect(res.pagination.hasNextPage, isTrue);

      final staging = await plugin.getBundles(
        DatabaseBundleQueryOptions(
          where: const DatabaseBundleQueryWhere(channel: 'staging'),
          limit: 10,
          offset: 0,
        ),
      );
      expect(staging.data, isEmpty);
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

    test('getUpdateInfo (appVersion) returns null when no compatible bundle',
        () async {
      await plugin.appendBundle(_makeBundle(id: 'b1', targetAppVersion: '1.0.0'));
      await plugin.commitBundle();

      final info = await plugin.getUpdateInfo(
        AppVersionGetBundlesArgs(
          platform: Platform.android,
          bundleId: nilUuid,
          appVersion: '9.9.9',
          channel: 'production',
          minBundleId: nilUuid,
        ),
      );

      expect(info, isNull);
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

    test('getUpdateInfo (fingerprint) returns null on mismatch', () async {
      await plugin.appendBundle(_makeBundle(id: 'fp', fingerprintHash: 'fp1'));
      await plugin.commitBundle();

      final info = await plugin.getUpdateInfo(
        FingerprintGetBundlesArgs(
          platform: Platform.android,
          bundleId: nilUuid,
          fingerprintHash: 'nope',
        ),
      );

      expect(info, isNull);
    });
  });
}
