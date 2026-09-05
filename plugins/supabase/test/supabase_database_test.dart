import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';
import 'package:flutter_ota_kit_supabase/flutter_ota_kit_supabase.dart';
import 'package:test/test.dart';

import 'mock_supabase_client.dart';

late Store store;
late FakeStorageBucket bucket;
late SupabaseClientLike client;

DatabasePlugin newPlugin() => supabaseDatabase(
  SupabaseServiceRoleConfig(
    supabaseUrl: 'https://test.supabase.invalid',
    supabaseAnonKey: 'test-anon-key',
    clientFactory: (_, __) => client,
  ),
)();

Bundle _bundle(
  String id, {
  bool enabled = true,
  String? fp,
  String? message,
  String channel = 'production',
}) => Bundle(
  id: id,
  platform: Platform.android,
  shouldForceUpdate: false,
  enabled: enabled,
  fileHash: 'file-$id',
  gitCommitHash: 'git-$id',
  message: message ?? 'msg-$id',
  channel: channel,
  storageUri: 'supabase-storage://updates/bundles/$id.zip',
  targetAppVersion: '1.0.0',
  fingerprintHash: fp,
  metadata: const BundleMetadata(),
  manifestStorageUri: 'supabase-storage://updates/manifests/$id.json',
  manifestFileHash: 'mf-$id',
  assetBaseStorageUri: 'supabase-storage://updates/assets',
);

void main() {
  setUp(() {
    store = Store();
    bucket = FakeStorageBucket();
    client = createMockSupabaseClient(store: store, bucket: bucket);
  });

  group('supabaseDatabase bundle methods', () {
    test('insert + commit + getBundleById round-trips', () async {
      final plugin = newPlugin();
      await plugin.appendBundle(_bundle('b1'));
      await plugin.commitBundle();
      final got = await plugin.getBundleById('b1');
      expect(got, isNotNull);
      expect(got!.id, 'b1');
      expect(got.fileHash, 'file-b1');
      expect(got.targetAppVersion, '1.0.0');
      expect(got.rolloutCohortCount, 1000);
    });

    test('getBundles filters by where + pagination', () async {
      final plugin = newPlugin();
      for (var i = 0; i < 5; i++) {
        await plugin.appendBundle(_bundle('b$i'));
      }
      await plugin.commitBundle();

      final res = await plugin.getBundles(
        DatabaseBundleQueryOptions(
          where: DatabaseBundleQueryWhere(
            channel: 'production',
            platform: Platform.android,
          ),
          limit: 3,
        ),
      );
      expect(res.data, hasLength(3));
      expect(res.pagination.total, 5);
    });

    test('getChannels returns distinct channels', () async {
      final plugin = newPlugin();
      await plugin.appendBundle(_bundle('b1'));
      await plugin.appendBundle(_bundle('b2', channel: 'staging'));
      await plugin.commitBundle();
      final channels = await plugin.getChannels();
      expect(channels, containsAll(['production', 'staging']));
      expect(channels, hasLength(2));
    });

    test('updateBundle persists changes', () async {
      final plugin = newPlugin();
      await plugin.appendBundle(_bundle('b1'));
      await plugin.commitBundle();
      final updated = _bundle('b1', message: 'updated');
      await plugin.updateBundle('b1', updated.toJson());
      await plugin.commitBundle();
      final got = await plugin.getBundleById('b1');
      expect(got!.message, 'updated');
    });

    test('deleteBundle removes the row', () async {
      final plugin = newPlugin();
      await plugin.appendBundle(_bundle('b1'));
      await plugin.commitBundle();
      final got = await plugin.getBundleById('b1');
      await plugin.deleteBundle(got!);
      await plugin.commitBundle();
      expect(await plugin.getBundleById('b1'), isNull);
    });
  });

  group('supabaseDatabase getUpdateInfo via RPC', () {
    test('appVersion strategy returns newer enabled bundle', () async {
      final plugin = newPlugin();
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000001'),
      );
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000002'),
      );
      await plugin.commitBundle();

      final info = await plugin.getUpdateInfo(
        AppVersionGetBundlesArgs(
          appVersion: '1.0.0',
          bundleId: '018f0000-0000-7000-8000-000000000001',
          channel: 'production',
          minBundleId: nilUuid,
          platform: Platform.android,
        ),
      );
      expect(info, isNotNull);
      expect(info!.id, '018f0000-0000-7000-8000-000000000002');
      expect(info.status, UpdateStatus.update);
    });

    test('fingerprint strategy returns matching bundle', () async {
      final plugin = newPlugin();
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000001', fp: 'fp-current'),
      );
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000002', fp: 'fp-target'),
      );
      await plugin.commitBundle();

      final info = await plugin.getUpdateInfo(
        FingerprintGetBundlesArgs(
          fingerprintHash: 'fp-target',
          bundleId: '018f0000-0000-7000-8000-000000000001',
          channel: 'production',
          minBundleId: nilUuid,
          platform: Platform.android,
        ),
      );
      expect(info, isNotNull);
      expect(info!.id, '018f0000-0000-7000-8000-000000000002');
    });

    test('returns rollback when no compatible newer bundle exists', () async {
      final plugin = newPlugin();
      await plugin.appendBundle(
        _bundle('018f0000-0000-7000-8000-000000000001'),
      );
      await plugin.commitBundle();

      final info = await plugin.getUpdateInfo(
        AppVersionGetBundlesArgs(
          appVersion: '9.9.9',
          bundleId: '018f0000-0000-7000-8000-000000000001',
          channel: 'production',
          minBundleId: nilUuid,
          platform: Platform.android,
        ),
      );
      expect(info, isNotNull);
      expect(info!.status, UpdateStatus.rollback);
    });

    test('returns null for an init bundle with no candidates', () async {
      final plugin = newPlugin();
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
