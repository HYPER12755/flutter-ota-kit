import 'package:flutter_patcher_aws/flutter_patcher_aws.dart';
import 'package:flutter_patcher_cloudflare/flutter_patcher_cloudflare.dart';
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart';
import 'package:flutter_patcher_postgres/flutter_patcher_postgres.dart';
import 'package:flutter_patcher_standalone/flutter_patcher_standalone.dart';
import 'package:flutter_patcher_supabase/flutter_patcher_supabase.dart';

import 'config.dart';

/// Backend handle wiring the database + node storage profiles used by the CLI.
class Backend {
  const Backend({
    required this.db,
    required this.storage,
    this.basePath,
  });

  final DatabasePlugin db;
  final NodeStorageProfile storage;

  /// Optional storage key prefix (e.g. "bundles") honored when building keys.
  final String? basePath;

  /// Build the storage object key for a bundle artifact.
  String storageKeyFor(String bundleId, String file) {
    final parts = [
      if (basePath != null && basePath!.isNotEmpty) basePath!,
      bundleId,
      file,
    ];
    return parts.join('/');
  }
}

/// Construct a [Backend] for the configured provider.
///
/// Supports `supabase`, `postgres`, `cloudflare`, and `aws`. Credential
/// precedence is: explicit factory/flag > environment variable > JSON config
/// (see the `resolve*Config` helpers in `config.dart`). Test seams let callers
/// inject mock clients (e.g. `postgresClientFactory`).
Backend resolveBackend(
  FlutterPatcherConfig config, {
  SupabaseClientFactory? supabaseClientFactory,
  D1ClientFactory? d1ClientFactory,
  R2S3ClientFactory? r2ClientFactory,
  PostgresClientFactory? postgresClientFactory,
  AwsS3ClientLike Function(S3DatabaseConfig config)? awsS3ClientFactory,
  AwsCloudFrontClientLike Function(S3DatabaseConfig config)?
      awsCloudFrontClientFactory,
  AwsS3ClientLike Function(AwsS3StorageConfig config)? awsStorageClientFactory,
  StandaloneClientFactory? standaloneClientFactory,
}) {
  switch (config.provider) {
    case 'supabase':
      final dbConfig = resolveSupabaseConfig(
        config,
        clientFactory: supabaseClientFactory,
      );
      final storageConfig = resolveSupabaseStorageConfig(
        config,
        clientFactory: supabaseClientFactory,
      );
      final db = supabaseDatabase(dbConfig)();
      final storage = supabaseStorage(storageConfig);
      final node = storage.profiles.node;
      if (node == null) {
        throw StateError('Supabase storage plugin exposes no node profile.');
      }
      return Backend(
        db: db,
        storage: node,
        basePath: storageConfig.basePath,
      );

    case 'postgres':
      final dbConfig = resolvePostgresDatabaseConfig(
        config,
        clientFactory: postgresClientFactory,
      );
      final storageConfig = resolvePostgresStorageConfig(
        config,
        clientFactory: postgresClientFactory,
      );
      final db = postgresDatabase(dbConfig)();
      final storage = postgresStorage(storageConfig);
      final node = storage.profiles.node;
      if (node == null) {
        throw StateError('Postgres storage plugin exposes no node profile.');
      }
      return Backend(
        db: db,
        storage: node,
        basePath: storageConfig.basePath,
      );

    case 'cloudflare':
      final dbConfig = resolveCloudflareDatabaseConfig(
        config,
        clientFactory: d1ClientFactory,
      );
      final storageConfig = resolveCloudflareStorageConfig(
        config,
        clientFactory: r2ClientFactory,
      );
      final db = d1Database(dbConfig)();
      final storage = r2Storage(storageConfig);
      final node = storage.profiles.node;
      if (node == null) {
        throw StateError('R2 storage plugin exposes no node profile.');
      }
      return Backend(
        db: db,
        storage: node,
        basePath: storageConfig.basePath,
      );

    case 'aws':
      final dbConfig = resolveAwsDatabaseConfig(
        config,
        clientFactory: awsS3ClientFactory,
        cloudfrontClientFactory: awsCloudFrontClientFactory,
      );
      final storageConfig = resolveAwsStorageConfig(
        config,
        clientFactory: awsStorageClientFactory,
      );
      final db = s3Database(dbConfig)();
      final storage = s3Storage(storageConfig);
      final node = storage.profiles.node;
      if (node == null) {
        throw StateError('S3 storage plugin exposes no node profile.');
      }
      return Backend(
        db: db,
        storage: node,
        basePath: storageConfig.basePath,
      );

    case 'standalone':
      final dbConfig = resolveStandaloneDatabaseConfig(
        config,
        clientFactory: standaloneClientFactory,
      );
      final storageConfig = resolveStandaloneStorageConfig(
        config,
        clientFactory: standaloneClientFactory,
      );
      final db = standaloneRepository(dbConfig)();
      final storage = standaloneStorage(storageConfig);
      final node = storage.profiles.node;
      if (node == null) {
        throw StateError('Standalone storage plugin exposes no node profile.');
      }
      return Backend(db: db, storage: node);

    default:
      throw UnsupportedError(
        'Provider "${config.provider}" is not supported. '
        'Supported: supabase, postgres, cloudflare, aws, standalone.',
      );
  }
}