import 'dart:convert' show utf8;

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show StorageObject;

import 'package:flutter_ota_kit_aws/flutter_ota_kit_aws.dart'
    show AwsS3ClientLike, AwsS3StorageConfig;

/// In-memory store backing [MockAwsS3Client].
class Store {
  final Map<String, List<int>> objects = {};
}

/// Mock AWS S3 client that stores objects in memory.
class MockAwsS3Client implements AwsS3ClientLike {
  MockAwsS3Client(this.store, {this.bucketName = 'bucket'});

  final Store store;
  final String bucketName;

  @override
  Future<void> deleteObject(String key) async => store.objects.remove(key);

  @override
  Future<void> deleteObjects(List<String> keys) async {
    for (final key in keys) {
      store.objects.remove(key);
    }
  }

  @override
  Future<bool> headObject(String key) async => store.objects.containsKey(key);

  @override
  Future<List<int>> getObjectAsBytes(String key) async {
    final bytes = store.objects[key];
    if (bytes == null) throw Exception('NoSuchKey: $key');
    return bytes;
  }

  @override
  Future<String> getObjectAsString(String key) async =>
      utf8.decode(await getObjectAsBytes(key));

  @override
  Future<String> getPresignedUrl(String key, {int expiresIn = 3600}) async =>
      'https://$bucketName.s3.us-east-1.amazonaws.com/$bucketName/$key'
      '?X-Amz-Signature=mock&X-Amz-Expires=$expiresIn';

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async {
    final p = prefix ?? '';
    return store.objects.keys
        .where((k) => k.startsWith(p))
        .map(
          (k) => StorageObject(
            key: k,
            storageUri: 's3://$bucketName/$k',
            size: store.objects[k]!.length,
          ),
        )
        .toList();
  }

  @override
  Future<void> putObject(String key, List<int> body, String contentType) async {
    store.objects[key] = body;
  }
}

/// Build an [AwsS3StorageConfig] wired to an in-memory [Store].
AwsS3StorageConfig mockConfig(Store store) => AwsS3StorageConfig(
  bucketName: 'test-bucket',
  region: 'us-east-1',
  accessKeyId: 'test-access-key',
  secretAccessKey: 'test-secret',
  clientFactory: (_) => MockAwsS3Client(store),
);
