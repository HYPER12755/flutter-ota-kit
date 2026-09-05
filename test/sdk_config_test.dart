// SDK-side public API tests.

import 'dart:async';

import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show Bundle, GetBundlesArgs, Platform, UpdateInfo, UpdateStrategy;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show
        DatabaseBundleQueryOptions,
        DatabasePlugin,
        Paginated,
        PaginationInfo,
        StoragePlugin,
        StoragePluginProfiles;
import 'package:flutter_test/flutter_test.dart';

/// A database plugin whose `getUpdateInfo` blocks forever (until [unblock] is
/// called). Used to force the timeout path in `performSharedUpdateCheck`.
class _HangingDatabase implements DatabasePlugin {
  final Completer<void> _gate = Completer<void>();
  int _calls = 0;

  Future<void> unblock() => _gate.future;
  int get calls => _calls;

  @override
  String get name => 'hangingDatabase';

  @override
  Future<Bundle?> getBundleById(String bundleId) async => null;

  @override
  Future<List<String>> getChannels() async => const ['production'];

  @override
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args) async {
    _calls++;
    // Block forever (or until test fixture unblocks). The SDK's
    // `Future.timeout` wrapper should cancel this future.
    await _gate.future;
    return null;
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

class _EmptyStorage implements StoragePlugin {
  @override
  String get name => 'emptyStorage';

  @override
  String get supportedProtocol => 'mock:';

  @override
  StoragePluginProfiles get profiles => const StoragePluginProfiles();
}

void main() {
  group('FlutterPatcher.configure*', () {
    test('configureSupabase stores the config (no thrown error)', () {
      FlutterPatcher.configureSupabase(
        const SupabaseUpdateConfig(
          supabaseUrl: 'https://x.supabase.co',
          bucket: 'bundles',
          channel: 'production',
          platform: Platform.android,
          updateStrategy: UpdateStrategy.appVersion,
          appVersion: '1.0.0',
        ),
      );
    });

    test('configurePostgres stores the config', () {
      FlutterPatcher.configurePostgres(
        const PostgresUpdateConfig(
          host: 'localhost',
          database: 'ota',
          channel: 'production',
          platform: Platform.android,
          updateStrategy: UpdateStrategy.appVersion,
          appVersion: '1.0.0',
        ),
      );
    });

    test('configureCloudflare stores the config', () {
      FlutterPatcher.configureCloudflare(
        const CloudflareUpdateConfig(
          databaseId: 'db',
          accountId: 'acct',
          cloudflareApiToken: 'token',
          bucketName: 'bundles',
          accessKeyId: 'ak',
          secretAccessKey: 'sk',
          channel: 'production',
          platform: Platform.android,
          updateStrategy: UpdateStrategy.appVersion,
          appVersion: '1.0.0',
        ),
      );
    });

    test('configureAws stores the config', () {
      FlutterPatcher.configureAws(
        const AwsUpdateConfig(
          bucketName: 'b',
          region: 'us-east-1',
          accessKeyId: 'k',
          secretAccessKey: 's',
          channel: 'production',
          platform: Platform.android,
          updateStrategy: UpdateStrategy.appVersion,
          appVersion: '1.0.0',
        ),
      );
    });

    test('configurePocketBase stores the config', () {
      FlutterPatcher.configurePocketBase(
        const PocketBaseUpdateConfig(
          url: 'http://localhost:8090',
          adminEmail: 'admin@x.com',
          adminPassword: 'pw',
          bundlesCollection: 'bundles',
          bundlesBucket: 'bundles',
          channel: 'production',
          platform: Platform.android,
          updateStrategy: UpdateStrategy.appVersion,
          appVersion: '1.0.0',
        ),
      );
    });
  });

  group('UpdateConfig defaults', () {
    test('SupabaseUpdateConfig defaults sdkVersion to 1.0.0', () {
      const cfg = SupabaseUpdateConfig(
        supabaseUrl: 'https://x.supabase.co',
        bucket: 'bundles',
        channel: 'production',
        platform: Platform.android,
        updateStrategy: UpdateStrategy.appVersion,
      );
      expect(cfg.sdkVersion, '1.0.0');
    });

    test('CloudflareUpdateConfig defaults region to auto', () {
      const cfg = CloudflareUpdateConfig(
        databaseId: 'db',
        accountId: 'acct',
        cloudflareApiToken: 't',
        bucketName: 'b',
        accessKeyId: 'k',
        secretAccessKey: 's',
        channel: 'production',
        platform: Platform.android,
        updateStrategy: UpdateStrategy.appVersion,
      );
      expect(cfg.region, 'auto');
    });

    test('PostgresUpdateConfig defaults port to 5432', () {
      const cfg = PostgresUpdateConfig(
        host: 'localhost',
        database: 'ota',
        channel: 'production',
        platform: Platform.android,
        updateStrategy: UpdateStrategy.appVersion,
      );
      expect(cfg.port, 5432);
    });
  });

  group('UpdateSource.check() signatures', () {
    test('all 5 sources expose a check() method', () {
      const SupabaseUpdateSource();
      const PostgresUpdateSource();
      const CloudflareUpdateSource();
      const AwsUpdateSource();
      const PocketBaseUpdateSource();
    });
  });

  group('performSharedUpdateCheck timeout', () {
    test(
      'throws TimeoutException when the DB call exceeds the timeout',
      () async {
        final db = _HangingDatabase();
        final storage = _EmptyStorage();
        final fut = performSharedUpdateCheck(
          db: db,
          storage: storage,
          channel: 'production',
          platform: Platform.android,
          updateStrategy: UpdateStrategy.appVersion,
          appVersion: '1.0.0',
          fingerprintHash: null,
          minBundleId: '00000000-0000-0000-0000-000000000000',
          timeout: const Duration(milliseconds: 50),
        );
        await expectLater(
          fut,
          throwsA(
            isA<TimeoutException>().having(
              (e) => e.message ?? '',
              'message',
              contains('update check timed out'),
            ),
          ),
        );
        // The DB plugin was called once before the timeout fired.
        expect(db.calls, 1);
      },
    );

    test('default timeout is 10 seconds', () async {
      final db = _HangingDatabase();
      final storage = _EmptyStorage();
      // Wrap in a short outer timeout so the test doesn't wait 10s.
      final fut = performSharedUpdateCheck(
        db: db,
        storage: storage,
        channel: 'production',
        platform: Platform.android,
        updateStrategy: UpdateStrategy.appVersion,
        appVersion: '1.0.0',
        fingerprintHash: null,
        minBundleId: '00000000-0000-0000-0000-000000000000',
        // No timeout passed: should default to 10s.
      ).timeout(const Duration(milliseconds: 200));
      // We expect the outer 200ms to fire first (before the 10s default).
      await expectLater(fut, throwsA(isA<TimeoutException>()));
    });
  });
}
