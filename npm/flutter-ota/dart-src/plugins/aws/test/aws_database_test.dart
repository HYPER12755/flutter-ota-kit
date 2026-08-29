import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show
        AppVersionGetBundlesArgs,
        Bundle,
        Platform,
        nilUuid;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show DatabaseBundleQueryOptions, DatabasePlugin;
import 'package:flutter_ota_kit_aws/flutter_ota_kit_aws.dart'
    show S3DatabaseConfig, AwsS3ClientLike, AwsCloudFrontClientLike, s3Database;
import 'package:test/test.dart';

import 'mock_aws_s3_client.dart' show Store, MockAwsS3Client;

/// Records CloudFront invalidation calls for assertions.
class MockCloudFrontClient implements AwsCloudFrontClientLike {
  MockCloudFrontClient();

  final List<(String, List<String>)> invalidations = [];

  @override
  Future<void> createInvalidation(
    String distributionId,
    List<String> paths, {
    bool shouldWait = false,
  }) async {
    invalidations.add((distributionId, List<String>.from(paths)));
  }
}

Bundle _makeBundle({
  required String id,
  String channel = 'production',
  String? targetAppVersion,
  String? fingerprintHash,
}) =>
    Bundle(
      id: id,
      channel: channel,
      enabled: true,
      shouldForceUpdate: false,
      fileHash: 'h-$id',
      platform: Platform.android,
      targetAppVersion: targetAppVersion,
      storageUri: 's3://test-bucket/$id',
      fingerprintHash: fingerprintHash,
      message: 'msg-$id',
      patches: null,
    );

void main() {
  group('aws s3Database', () {
    late Store store;
    late MockCloudFrontClient cf;
    late DatabasePlugin plugin;

    S3DatabaseConfig config({
      required AwsS3ClientLike Function(S3DatabaseConfig) clientFactory,
      String? cloudfrontDistributionId,
    }) =>
        S3DatabaseConfig(
          bucketName: 'test-bucket',
          region: 'us-east-1',
          accessKeyId: 'ak',
          secretAccessKey: 'sk',
          clientFactory: clientFactory,
          cloudfrontDistributionId: cloudfrontDistributionId,
          cloudfrontClientFactory: (_) => cf,
        );

    setUp(() {
      store = Store();
      cf = MockCloudFrontClient();
      plugin = s3Database(config(
        clientFactory: (_) => MockAwsS3Client(store),
        cloudfrontDistributionId: 'DIST123',
      ))();
    });

    test('plugin metadata', () {
      expect(plugin.name, 's3Database');
    });

    test('commitBundle writes update.json and invalidates CloudFront',
        () async {
      await plugin.appendBundle(
        _makeBundle(id: 'b1', targetAppVersion: '1.0.0'),
      );
      await plugin.commitBundle();

      final keys = store.objects.keys.toList();
      expect(
        keys,
        contains('production/android/1.0.0/update.json'),
      );

      expect(cf.invalidations, isNotEmpty);
      expect(cf.invalidations.first.$1, 'DIST123');
    });

    test('getUpdateInfo (appVersion) resolves committed bundle', () async {
      await plugin.appendBundle(
        _makeBundle(id: 'b1', targetAppVersion: '1.0.0'),
      );
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
    });

    test('getBundles returns committed bundles', () async {
      await plugin.appendBundle(
        _makeBundle(id: 'b1', targetAppVersion: '1.0.0'),
      );
      await plugin.commitBundle();

      final result = await plugin.getBundles(
        const DatabaseBundleQueryOptions(limit: 100, offset: 0),
      );
      expect(result.data, hasLength(1));
      expect(result.data.first.id, 'b1');
    });

    test('deleteBundle removes update.json and invalidates', () async {
      await plugin.appendBundle(
        _makeBundle(id: 'b1', targetAppVersion: '1.0.0'),
      );
      await plugin.commitBundle();
      expect(store.objects.keys, contains('production/android/1.0.0/update.json'));

      cf.invalidations.clear();
      final bundle = (await plugin.getBundles(
        const DatabaseBundleQueryOptions(limit: 100, offset: 0),
      ))
          .data
          .first;
      await plugin.deleteBundle(bundle);
      await plugin.commitBundle();

      expect(
        store.objects.keys,
        isNot(contains('production/android/1.0.0/update.json')),
      );
      expect(cf.invalidations, isNotEmpty);
    });

    test('no CloudFront invalidation when distribution id omitted', () async {
      final noCf = s3Database(config(
        clientFactory: (_) => MockAwsS3Client(store),
      ))();
      await noCf.appendBundle(
        _makeBundle(id: 'b1', targetAppVersion: '1.0.0'),
      );
      await noCf.commitBundle();
      expect(cf.invalidations, isEmpty);
    });
  });
}
