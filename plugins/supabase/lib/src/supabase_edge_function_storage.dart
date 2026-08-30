/// Faithful port of hot-updater `plugins/supabase/src/supabaseEdgeFunctionStorage.ts`.
library;

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';

import 'supabase_client_adapter.dart';
import 'supabase_client_http.dart';
import 'supabase_signed_url_batcher.dart';
import 'error_message.dart' show errorMessage;

/// Config for the Supabase edge-function storage plugin.
class SupabaseEdgeFunctionStorageConfig {
  final String supabaseUrl;
  final String supabaseServiceRoleKey;
  final int? signedUrlExpiresIn;

  const SupabaseEdgeFunctionStorageConfig({
    required this.supabaseUrl,
    required this.supabaseServiceRoleKey,
    this.signedUrlExpiresIn,
  });

  SupabaseClientFactory get clientFactory =>
      (url, key) => createSupabaseHttpClient(url, key);
}

/// Parse a `supabase-storage://` URI into bucket + key.
ParsedStorageUri parseSupabaseEdgeStorageUri(String storageUri) =>
    parseStorageUri(storageUri, 'supabase-storage');

/// Edge-function variant of [supabaseStorage]: a runtime-only storage plugin
/// (no node profile) backed by the Supabase client.
final supabaseEdgeFunctionStorage =
    createRuntimeStoragePlugin<SupabaseEdgeFunctionStorageConfig>(
  name: 'supabaseEdgeFunctionStorage',
  supportedProtocol: 'supabase-storage',
  factory: (config) {
    final supabase = config.clientFactory(
      config.supabaseUrl,
      config.supabaseServiceRoleKey,
    );
    final resolveSignedUrl = createSupabaseSignedUrlBatcher(
      createSignedUrls: (bucketName, keys, expiresIn) =>
          supabase.storage.from(bucketName).createSignedUrls(keys, expiresIn),
      expiresIn: config.signedUrlExpiresIn ?? 3600,
      formatObjectPath: (bucketName, key) => '$bucketName/$key',
    );

    return RuntimeStorageProfileImplEdge(
      supabase: supabase,
      resolveSignedUrl: resolveSignedUrl,
    );
  },
);

class RuntimeStorageProfileImplEdge implements RuntimeStorageProfile {
  RuntimeStorageProfileImplEdge({
    required this.supabase,
    required this.resolveSignedUrl,
  });

  final SupabaseClientLike supabase;
  final ResolveSignedUrl resolveSignedUrl;

  @override
  Future<String?> readText(String storageUri) async {
    final parsed = parseSupabaseEdgeStorageUri(storageUri);
    if (parsed.bucket.isEmpty || parsed.key.isEmpty) {
      throw StateError('Invalid Supabase storage URI');
    }
    final res = await supabase.storage.from(parsed.bucket).download(parsed.key);
    if (res.error != null) {
      final msg = (res.message ?? errorMessage(res.error))
          .toString();
      if (msg.contains('not found')) return null;
      throw StateError('Failed to read storage text: $msg');
    }
    if (res.data == null) return null;
    return String.fromCharCodes(res.data!);
  }

  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async {
    final parsed = parseSupabaseEdgeStorageUri(storageUri);
    if (parsed.bucket.isEmpty || parsed.key.isEmpty) {
      throw StateError('Invalid Supabase storage URI');
    }
    final signedUrl = await resolveSignedUrl(parsed.bucket, parsed.key);
    return {'fileUrl': signedUrl};
  }
}
