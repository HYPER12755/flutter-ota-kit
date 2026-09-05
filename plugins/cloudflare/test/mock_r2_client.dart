import 'dart:convert' show utf8;

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show StorageObject;

import 'package:flutter_ota_kit_cloudflare/flutter_ota_kit_cloudflare.dart'
    show R2S3StorageConfig, R2S3ClientLike;

/// In-memory store backing [MockR2Client].
class Store {
  final Map<String, List<int>> objects = {};
}

/// Mock R2 S3 client that stores objects in memory.
class MockR2Client implements R2S3ClientLike {
  MockR2Client(this.store, {this.bucketName = 'bucket'});

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
  Future<String> getSignedUrl(String key, {int expiresIn = 3600}) async =>
      'https://$bucketName.r2.cloudflarestorage.com/$bucketName/$key'
      '?X-Amz-Signature=mock&X-Amz-Expires=$expiresIn';

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async {
    final p = prefix ?? '';
    return store.objects.keys
        .where((k) => k.startsWith(p))
        .map(
          (k) => StorageObject(
            key: k,
            storageUri: 'r2://$bucketName/$k',
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

/// Build an [R2S3StorageConfig] wired to an in-memory [Store].
R2S3StorageConfig mockR2Config(Store store) => R2S3StorageConfig(
  accountId: 'test-account',
  bucketName: 'test-bucket',
  accessKeyId: 'test-access-key',
  secretAccessKey: 'test-secret',
  clientFactory: (_) => MockR2Client(store),
);
