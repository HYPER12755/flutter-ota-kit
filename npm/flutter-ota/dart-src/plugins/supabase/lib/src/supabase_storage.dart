/// Faithful port of hot-updater `plugins/supabase/src/supabaseStorage.ts`.
library;

import 'dart:io' as io;

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';

import 'supabase_client_adapter.dart';
import 'supabase_client_http.dart';
import 'supabase_config.dart';
import 'supabase_signed_url_batcher.dart';

/// Parse a `supabase-storage://` URI into bucket + key.
ParsedStorageUri parseSupabaseStorageUri(String storageUri) =>
    parseStorageUri(storageUri, 'supabase-storage');

/// Configuration for the Supabase storage plugin.
class SupabaseStorageConfig extends SupabaseServiceRoleConfig {
  final String bucketName;

  /// Base path where bundles are stored in the bucket.
  final String? basePath;

  const SupabaseStorageConfig({
    required super.supabaseUrl,
    super.supabaseServiceRoleKey,
    super.supabaseAnonKey,
    super.clientFactory,
    required this.bucketName,
    this.basePath,
  });
}

String _getErrorMessage(Object? error) {
  if (error is Error) return error.toString();
  if (error is Exception) return error.toString();
  if (error is Map && error['message'] is String) {
    return error['message'] as String;
  }
  return error.toString();
}

Future<String> _createSignedUrlOrThrow({
  required SupabaseStorageBucketLike bucket,
  required String key,
  required int expiresIn,
}) async {
  late Object? error;
  String? signedUrl;
  try {
    final response = await bucket.createSignedUrl(key, expiresIn);
    signedUrl = response.signedUrl;
    error = response.error;
  } catch (thrown) {
    error = thrown;
  }

  if (error == null && signedUrl != null) {
    return signedUrl;
  }

  throw StateError(
    'Failed to generate download URL for "$key": '
    '${_getErrorMessage(error ?? StateError("missing signed URL"))}',
  );
}

Future<void> _verifyObjectCanBeSignedForRuntime({
  required SupabaseStorageBucketLike bucket,
  required String key,
}) async {
  await _createSignedUrlOrThrow(
    bucket: bucket,
    key: key,
    expiresIn: 3600,
  );
}

/// Supabase-backed universal (node + runtime) storage plugin.
final supabaseStorage = createUniversalStoragePlugin<SupabaseStorageConfig>(
  name: 'supabaseStorage',
  supportedProtocol: 'supabase-storage',
  factory: (config) {
    final supabase = config.clientFactory != null
        ? config.clientFactory!(config.supabaseUrl, config.resolveKey())
        : createSupabaseHttpClient(config.supabaseUrl, config.resolveKey());

    final bucket = supabase.storage.from(config.bucketName);
    final getStorageKey = createStorageKeyBuilder(config.basePath);
    final resolveSignedUrl = createSupabaseSignedUrlBatcher(
      createSignedUrls: (bucketName, keys, expiresIn) =>
          supabase.storage.from(bucketName).createSignedUrls(keys, expiresIn),
      expiresIn: 3600,
      formatObjectPath: (bucketName, key) => key,
    );

    return (
      node: NodeStorageProfileImpl(
        bucket: bucket,
        getStorageKey: getStorageKey,
        bucketName: config.bucketName,
        verifySigned: _verifyObjectCanBeSignedForRuntime,
        createSignedUrlOrThrow: _createSignedUrlOrThrow,
      ),
      runtime: RuntimeStorageProfileImpl(
        bucket: bucket,
        resolveSignedUrl: resolveSignedUrl,
        bucketName: config.bucketName,
      ),
    );
  },
);

class NodeStorageProfileImpl implements NodeStorageProfile {
  NodeStorageProfileImpl({
    required this.bucket,
    required this.getStorageKey,
    required this.bucketName,
    required this.verifySigned,
    required this.createSignedUrlOrThrow,
  });

  final SupabaseStorageBucketLike bucket;
  final String Function(String, [String, String, String]) getStorageKey;
  final String bucketName;
  final Future<void> Function({
    required SupabaseStorageBucketLike bucket,
    required String key,
  }) verifySigned;
  final Future<String> Function({
    required SupabaseStorageBucketLike bucket,
    required String key,
    required int expiresIn,
  }) createSignedUrlOrThrow;

  @override
  Future<Map<String, String>> upload(String key, String filePath) async {
    final body = await io.File(filePath).readAsBytes();
    final contentType = getContentType(filePath);
    final filename = filePath.split(io.Platform.pathSeparator).last;
    final storageKey = getStorageKey(key, filename);

    final upload = await bucket.upload(
      storageKey,
      body,
      contentType: contentType,
      cacheControl: 'max-age=31536000',
    );
    if (upload.error != null) {
      throw StateError(_getErrorMessage(upload.error));
    }

    await verifySigned(bucket: bucket, key: storageKey);
    return {
      'storageUri': 'supabase-storage://$bucketName/$storageKey',
    };
  }

  @override
  Future<bool> exists(String storageUri) async {
    final parsed = parseSupabaseStorageUri(storageUri);
    if (parsed.bucket != bucketName) {
      throw StateError(
        'Bucket name mismatch: expected "$bucketName", but found '
        '"${parsed.bucket}".',
      );
    }
    final res = await bucket.exists(parsed.key);
    if (res.data == false) return false;
    if (res.error != null) {
      throw StateError(_getErrorMessage(res.error));
    }
    await verifySigned(bucket: bucket, key: parsed.key);
    return res.data as bool;
  }

  @override
  Future<void> delete(String storageUri) async {
    final parsed = parseSupabaseStorageUri(storageUri);
    if (parsed.bucket != bucketName) {
      throw StateError(
        'Bucket name mismatch: expected "$bucketName", but found '
        '"${parsed.bucket}".',
      );
    }
    final res = await bucket.remove([parsed.key]);
    if (res.error != null) {
      final msg = res.message ?? _getErrorMessage(res.error);
      if (msg.contains('not found')) {
        throw StateError('Bundle not found');
      }
      throw StateError('Failed to delete bundle: $msg');
    }
  }

  @override
  Future<void> downloadFile(String storageUri, String filePath) async {
    final parsed = parseSupabaseStorageUri(storageUri);
    if (parsed.bucket != bucketName) {
      throw StateError(
        'Bucket name mismatch: expected "$bucketName", but found '
        '"${parsed.bucket}".',
      );
    }
    final res = await bucket.download(parsed.key);
    if (res.error != null) {
      throw StateError('Failed to download bundle: ${res.message}');
    }
    if (res.data == null) {
      throw StateError('Failed to download bundle');
    }
    final dir = filePath.substring(0, filePath.lastIndexOf(io.Platform.pathSeparator));
    await io.Directory(dir).create(recursive: true);
    await io.File(filePath).writeAsBytes(res.data!);
  }

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async {
    final res = await bucket.list(prefix);
    if (res.error != null) {
      throw StateError(
        'Failed to list objects: ${_getErrorMessage(res.error)}',
      );
    }
    final data = res.data ?? const <SupabaseStorageObject>[];
    return data
        .map(
          (o) => StorageObject(
            key: o.key,
            storageUri: 'supabase-storage://$bucketName/${o.key}',
            size: o.size,
            lastModifiedAt: o.lastModifiedAt != null
                ? DateTime.tryParse(o.lastModifiedAt!)
                : null,
          ),
        )
        .toList();
  }

  @override
  Future<void> deleteObjects(List<String> keys) async {
    if (keys.isEmpty) return;
    final res = await bucket.remove(keys);
    if (res.error != null) {
      final msg = res.message ?? _getErrorMessage(res.error);
      if (!msg.contains('not found')) {
        throw StateError('Failed to delete objects: $msg');
      }
    }
  }
}

class RuntimeStorageProfileImpl implements RuntimeStorageProfile {
  RuntimeStorageProfileImpl({
    required this.bucket,
    required this.resolveSignedUrl,
    required this.bucketName,
  });

  final SupabaseStorageBucketLike bucket;
  final ResolveSignedUrl resolveSignedUrl;
  final String bucketName;

  @override
  Future<String?> readText(String storageUri) async {
    final parsed = parseSupabaseStorageUri(storageUri);
    if (parsed.bucket != bucketName) {
      throw StateError(
        'Bucket name mismatch: expected "$bucketName", but found '
        '"${parsed.bucket}".',
      );
    }
    final res = await bucket.download(parsed.key);
    if (res.error != null) {
      final msg = res.message ?? _getErrorMessage(res.error);
      if (msg.contains('not found')) return null;
      throw StateError('Failed to read storage text: $msg');
    }
    if (res.data == null) return null;
    return String.fromCharCodes(res.data!);
  }

  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async {
    final parsed = parseSupabaseStorageUri(storageUri);
    if (parsed.bucket != bucketName) {
      throw StateError(
        'Bucket name mismatch: expected "$bucketName", but found '
        '"${parsed.bucket}".',
      );
    }
    final signedUrl = await resolveSignedUrl(bucketName, parsed.key);
    return {'fileUrl': signedUrl};
  }
}
