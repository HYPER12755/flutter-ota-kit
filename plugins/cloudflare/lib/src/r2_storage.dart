import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show StoragePlugin, createUniversalStoragePlugin;

import 'r2_config.dart' show R2S3StorageConfig;
import 'r2_storage_profile.dart'
    show createS3RuntimeStorageProfile, createS3StorageProfile;

/// Cloudflare R2 storage plugin (faithful port of hot-updater's `r2Storage`).
///
/// Uses the S3-compatible R2 API (AWS Signature V4). The node profile handles
/// upload/delete/download/list; the runtime profile serves presigned download
/// URLs and reads small text objects. Note: hot-updater also supports a
/// deprecated Wrangler-CLI based profile; only the S3-compatible profile is
/// ported here.
final StoragePlugin Function(R2S3StorageConfig config) r2Storage =
    createUniversalStoragePlugin<R2S3StorageConfig>(
  name: 'r2Storage',
  supportedProtocol: 'r2',
  factory: (config) => (
    node: createS3StorageProfile(config),
    runtime: createS3RuntimeStorageProfile(config),
  ),
);
