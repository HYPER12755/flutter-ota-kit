import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show createUniversalStoragePlugin;

import 'aws_config.dart' show AwsS3StorageConfig;
import 'aws_storage_profile.dart'
    show createS3RuntimeStorageProfile, createS3StorageProfile;

/// AWS S3 storage plugin (faithful port of hot-updater `s3Storage.ts`).
///
/// Stores bundles as objects in an S3 bucket and serves presigned GET URLs at
/// runtime. Uses AWS Signature V4 (virtual-hosted addressing).
final s3Storage = createUniversalStoragePlugin<AwsS3StorageConfig>(
  name: 's3Storage',
  supportedProtocol: 's3',
  factory: (config) => (
    node: createS3StorageProfile(config),
    runtime: createS3RuntimeStorageProfile(config),
  ),
);
