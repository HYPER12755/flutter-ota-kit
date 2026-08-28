import 'dart:io';

import 'package:flutter_patcher_aws/flutter_patcher_aws.dart';
import 'package:flutter_patcher_cli/flutter_patcher_cli.dart';
import 'package:flutter_patcher_cloudflare/flutter_patcher_cloudflare.dart';
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart';
import 'package:test/test.dart';

import 'mocks/mock_aws_s3_client.dart' as aws;
import 'mocks/mock_d1_client.dart' as d1;
import 'mocks/mock_postgres_client.dart' as pg;

// --- R2 (cloudflare storage) mock ------------------------------------------

class MockR2Client implements R2S3ClientLike {
  MockR2Client(this.store);
  final aws.Store store;

  @override
  Future<void> deleteObject(String key) async => store.objects.remove(key);
  @override
  Future<void> deleteObjects(List<String> keys) async =>
      keys.forEach(store.objects.remove);
  @override
  Future<bool> headObject(String key) async => store.objects.containsKey(key);
  @override
  Future<List<int>> getObjectAsBytes(String key) async =>
      store.objects[key] ?? (throw Exception('NoSuchKey: $key'));
  @override
  Future<String> getObjectAsString(String key) async =>
      String.fromCharCodes(await getObjectAsBytes(key));
  @override
  Future<String> getSignedUrl(String key, {int expiresIn = 3600}) async =>
      'https://r2.mock/$key?sig=mock&expires=$expiresIn';
  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async {
    final p = prefix ?? '';
    return store.objects.keys
        .where((k) => k.startsWith(p))
        .map((k) => StorageObject(
              key: k,
              storageUri: 'r2://$k',
              size: store.objects[k]!.length,
            ))
        .toList();
  }

  @override
  Future<void> putObject(String key, List<int> body, String contentType) async =>
      store.objects[key] = body;
}

// --- CloudFront (aws db invalidation) mock ----------------------------------

class MockCloudFrontClient implements AwsCloudFrontClientLike {
  @override
  Future<void> createInvalidation(
    String distributionId,
    List<String> paths, {
    bool shouldWait = false,
  }) async {
    // No-op for tests.
  }
}

// --- helpers ----------------------------------------------------------------

Directory makeSource() {
  final dir = Directory.systemTemp.createTempSync('fp-src-');
  File('${dir.path}/app.so').writeAsStringSync('fake-libapp-bytes');
  return dir;
}

FlutterPatcherConfig cfgFor(String provider) => FlutterPatcherConfig(
      provider: provider,
      supabase: const SupabaseConfigJson(url: 'https://x.supabase.co'),
      postgres: const PostgresConfigJson(host: 'mock', database: 'mock'),
      cloudflare: const CloudflareConfigJson(
        accountId: 'acct',
        d1DatabaseId: 'dbid',
        apiToken: 'token',
        r2Bucket: 'bundles',
        r2AccessKeyId: 'rk',
        r2SecretAccessKey: 'rs',
      ),
      aws: const AwsConfigJson(
        bucket: 'b',
        region: 'us-east-1',
        accessKeyId: 'k',
        secretAccessKey: 's',
      ),
      channel: 'production',
      platform: 'android',
      source: './dist',
    );

Future<void> runBackendLifecycle(String name, Backend backend) async {
  final source = makeSource();
  try {
    final bundle = await deployBundle(
      backend,
      DeployOptions(
        source: source.path,
        channel: 'production',
        platform: 'android',
        message: 'first',
        targetAppVersion: '>=1.0.0',
      ),
    );
    expect(bundle.id, isNotEmpty, reason: '$name: deployed id');
    expect(bundle.storageUri, isNotEmpty, reason: '$name: storageUri set');

    // The artifact bytes were actually uploaded to storage.
    expect(await backend.storage.exists(bundle.storageUri), isTrue,
        reason: '$name: storage has bundle');

    // Node profile can download the bytes back.
    final dl = File('${Directory.systemTemp.path}/fp-dl-${bundle.id}.zip');
    await backend.storage.downloadFile(bundle.storageUri, dl.path);
    expect(dl.existsSync() && await dl.length() > 0, isTrue,
        reason: '$name: download succeeds');
    await dl.delete();

    // listBundles round-trips.
    final listed = await listBundles(backend, const ListOptions());
    final found = listed.data.where((b) => b.id == bundle.id).toList();
    expect(found, hasLength(1), reason: '$name: bundle listed');

    // getChannel resolves the live (enabled) bundle.
    final live = await getChannel(backend, 'production');
    expect(live?.id, bundle.id, reason: '$name: channel live');

    // promote a second bundle, then rollback disables the latest.
    final second = await deployBundle(
      backend,
      DeployOptions(
        source: source.path,
        channel: 'production',
        platform: 'android',
        message: 'second',
        targetAppVersion: '>=1.0.0',
      ),
    );
    await promoteBundle(backend, second.id, 'production');
    final disabled = await rollbackChannel(backend, 'production');
    expect(disabled, second.id, reason: '$name: rollback disabled latest');

    // delete removes the bundle.
    await deleteBundle(backend, bundle.id);
    final afterDelete = await listBundles(
      backend,
      ListOptions(channel: 'production'),
    );
    expect(
      afterDelete.data.where((b) => b.id == bundle.id).isEmpty,
      isTrue,
      reason: '$name: bundle deleted',
    );
  } finally {
    source.deleteSync(recursive: true);
  }
}

// --- tests ------------------------------------------------------------------

void main() {
  group('cli backends', () {
    test('postgres backend (postgresDatabase + postgresStorage)', () async {
      final store = pg.Store();
      final backend = resolveBackend(
        cfgFor('postgres'),
        postgresClientFactory: (_) => pg.MockPostgresClient(store),
      );
      await runBackendLifecycle('postgres', backend);
    });

    test('cloudflare backend (d1Database + r2Storage)', () async {
      final dbStore = d1.Store();
      final r2Store = aws.Store();
      final backend = resolveBackend(
        cfgFor('cloudflare'),
        d1ClientFactory: (_) => d1.MockD1Client(dbStore),
        r2ClientFactory: (_) => MockR2Client(r2Store),
      );
      await runBackendLifecycle('cloudflare', backend);
    });

    test('aws backend (s3Database + s3Storage)', () async {
      final dbStore = aws.Store();
      final storageStore = aws.Store();
      final backend = resolveBackend(
        cfgFor('aws'),
        awsS3ClientFactory: (_) => aws.MockAwsS3Client(dbStore),
        awsCloudFrontClientFactory: (_) => MockCloudFrontClient(),
        awsStorageClientFactory: (_) => aws.MockAwsS3Client(storageStore),
      );
      await runBackendLifecycle('aws', backend);
    });

    test('resolveBackend rejects unknown provider', () {
      expect(
        () => resolveBackend(cfgFor('bogus')),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
