import 'dart:convert';
import 'dart:io';

import 'package:flutter_patcher_aws/flutter_patcher_aws.dart';
import 'package:postgres/postgres.dart';
import 'package:flutter_patcher_cloudflare/flutter_patcher_cloudflare.dart';
import 'package:flutter_patcher_postgres/flutter_patcher_postgres.dart';
import 'package:flutter_patcher_standalone/flutter_patcher_standalone.dart';
import 'package:flutter_patcher_supabase/flutter_patcher_supabase.dart';
import 'package:path/path.dart' as p;

/// Resolved configuration for the flutter_patcher CLI.
///
/// Mirrors hot-updater's config precedence: explicit flags > environment
/// variables > the project `.flutter_patcher.json` (falling back to the global
/// `~/.flutter_patcher/config.json`).
class FlutterPatcherConfig {
  FlutterPatcherConfig({
    required this.provider,
    required this.supabase,
    this.postgres = const PostgresConfigJson(),
    this.cloudflare = const CloudflareConfigJson(),
    this.aws = const AwsConfigJson(),
    this.standalone = const StandaloneConfigJson(),
    this.channel = 'production',
    this.platform = 'android',
    this.source = './dist',
    this.publicKey,
  });

  factory FlutterPatcherConfig.fromJson(Map<String, dynamic> json) =>
      FlutterPatcherConfig(
        provider: json['provider'] as String? ?? 'supabase',
        supabase: SupabaseConfigJson.fromJson(
          (json['supabase'] as Map?)?.cast<String, dynamic>() ?? {},
        ),
        postgres: PostgresConfigJson.fromJson(
          (json['postgres'] as Map?)?.cast<String, dynamic>() ?? {},
        ),
        cloudflare: CloudflareConfigJson.fromJson(
          (json['cloudflare'] as Map?)?.cast<String, dynamic>() ?? {},
        ),
        aws: AwsConfigJson.fromJson(
          (json['aws'] as Map?)?.cast<String, dynamic>() ?? {},
        ),
        standalone: StandaloneConfigJson.fromJson(
          (json['standalone'] as Map?)?.cast<String, dynamic>() ?? {},
        ),
        channel: json['channel'] as String? ?? 'production',
        platform: json['platform'] as String? ?? 'android',
        source: json['source'] as String? ?? './dist',
        publicKey: json['publicKey'] as String?,
      );

  final String provider;
  final SupabaseConfigJson supabase;
  final PostgresConfigJson postgres;
  final CloudflareConfigJson cloudflare;
  final AwsConfigJson aws;
  final StandaloneConfigJson standalone;
  final String channel;
  final String platform;
  final String source;
  final String? publicKey;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'supabase': supabase.toJson(),
        'postgres': postgres.toJson(),
        'cloudflare': cloudflare.toJson(),
        'aws': aws.toJson(),
        'standalone': standalone.toJson(),
        'channel': channel,
        'platform': platform,
        'source': source,
        if (publicKey != null) 'publicKey': publicKey,
      };

  FlutterPatcherConfig copyWith({
    String? provider,
    SupabaseConfigJson? supabase,
    PostgresConfigJson? postgres,
    CloudflareConfigJson? cloudflare,
    AwsConfigJson? aws,
    StandaloneConfigJson? standalone,
    String? channel,
    String? platform,
    String? source,
    String? publicKey,
  }) =>
      FlutterPatcherConfig(
        provider: provider ?? this.provider,
        supabase: supabase ?? this.supabase,
        postgres: postgres ?? this.postgres,
        cloudflare: cloudflare ?? this.cloudflare,
        aws: aws ?? this.aws,
        standalone: standalone ?? this.standalone,
        channel: channel ?? this.channel,
        platform: platform ?? this.platform,
        source: source ?? this.source,
        publicKey: publicKey ?? this.publicKey,
      );
}

/// Supabase section of [FlutterPatcherConfig].
class SupabaseConfigJson {
  const SupabaseConfigJson({
    this.url,
    this.serviceRoleKey,
    this.anonKey,
    this.bucket,
    this.basePath,
  });

  factory SupabaseConfigJson.fromJson(Map<String, dynamic> json) =>
      SupabaseConfigJson(
        url: json['url'] as String?,
        serviceRoleKey: json['serviceRoleKey'] as String?,
        anonKey: json['anonKey'] as String?,
        bucket: json['bucket'] as String?,
        basePath: json['basePath'] as String?,
      );

  final String? url;
  final String? serviceRoleKey;
  final String? anonKey;
  final String? bucket;
  final String? basePath;

  Map<String, dynamic> toJson() => {
        if (url != null) 'url': url,
        if (serviceRoleKey != null) 'serviceRoleKey': serviceRoleKey,
        if (anonKey != null) 'anonKey': anonKey,
        if (bucket != null) 'bucket': bucket,
        if (basePath != null) 'basePath': basePath,
      };
}

/// Search order for a config file on disk.
List<File> configCandidates() {
  final cwd = File(p.join(Directory.current.path, '.flutter_patcher.json'));
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';
  final global = File(p.join(home, '.flutter_patcher', 'config.json'));
  return [cwd, global];
}

/// Load the first existing config (cwd first, then global). Returns `null` if
/// neither exists.
FlutterPatcherConfig? loadConfig() {
  for (final file in configCandidates()) {
    if (file.existsSync()) {
      final raw = file.readAsStringSync();
      if (raw.trim().isEmpty) continue;
      return FlutterPatcherConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    }
  }
  return null;
}

/// Persist a config to the project file (cwd).
void saveConfig(FlutterPatcherConfig config) {
  final file = configCandidates().first;
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(config.toJson()),
  );
}

/// Nested dot-path get/set helpers used by `config get/set`.
Object? readPath(Map<String, dynamic> map, String path) {
  final parts = path.split('.');
  Object? current = map;
  for (final part in parts) {
    if (current is! Map) return null;
    current = current[part];
  }
  return current;
}

void writePath(Map<String, dynamic> map, String path, Object? value) {
  final parts = path.split('.');
  Map<String, dynamic> current = map;
  for (var i = 0; i < parts.length - 1; i++) {
    final part = parts[i];
    final next = current[part];
    if (next is Map<String, dynamic>) {
      current = next;
    } else {
      current[part] = <String, dynamic>{};
      current = current[part] as Map<String, dynamic>;
    }
  }
  current[parts.last] = value;
}

/// Resolve Supabase credentials honoring flag > env > config precedence.
SupabaseServiceRoleConfig resolveSupabaseConfig(
  FlutterPatcherConfig config, {
  String? url,
  String? serviceRoleKey,
  String? anonKey,
  String? bucket,
  String? basePath,
  SupabaseClientFactory? clientFactory,
}) {
  final env = Platform.environment;
  final resolvedUrl = url ?? env['SUPABASE_URL'] ?? config.supabase.url;
  final resolvedService = serviceRoleKey ??
      env['SUPABASE_SERVICE_ROLE_KEY'] ??
      config.supabase.serviceRoleKey;
  final resolvedAnon =
      anonKey ?? env['SUPABASE_ANON_KEY'] ?? config.supabase.anonKey;

  if (resolvedUrl == null || resolvedUrl.isEmpty) {
    throw StateError(
      'Supabase URL is required. Set it via --url, SUPABASE_URL, or '
      '`flutter_patcher config set supabase.url <url>`.',
    );
  }

  return SupabaseServiceRoleConfig(
    supabaseUrl: resolvedUrl,
    supabaseServiceRoleKey: resolvedService,
    supabaseAnonKey: resolvedAnon,
    clientFactory: clientFactory,
  );
}

/// Resolve the Supabase storage config (mirrors [resolveSupabaseConfig]).
SupabaseStorageConfig resolveSupabaseStorageConfig(
  FlutterPatcherConfig config, {
  String? url,
  String? serviceRoleKey,
  String? anonKey,
  String? bucket,
  String? basePath,
  SupabaseClientFactory? clientFactory,
}) {
  final db = resolveSupabaseConfig(
    config,
    url: url,
    serviceRoleKey: serviceRoleKey,
    anonKey: anonKey,
    bucket: bucket,
    basePath: basePath,
    clientFactory: clientFactory,
  );
  return SupabaseStorageConfig(
    supabaseUrl: db.supabaseUrl,
    supabaseServiceRoleKey: db.supabaseServiceRoleKey,
    supabaseAnonKey: db.supabaseAnonKey,
    clientFactory: db.clientFactory,
    bucketName: db.supabaseServiceRoleKey != null || db.supabaseAnonKey != null
        ? (bucket ??
            Platform.environment['SUPABASE_BUCKET'] ??
            config.supabase.bucket ??
            'bundles')
        : (bucket ?? config.supabase.bucket ?? 'bundles'),
    basePath: basePath ??
        Platform.environment['SUPABASE_BASE_PATH'] ??
        config.supabase.basePath,
  );
}

// ---------------------------------------------------------------------------
// Postgres backend config
// ---------------------------------------------------------------------------

/// Postgres section of [FlutterPatcherConfig].
class PostgresConfigJson {
  const PostgresConfigJson({
    this.host,
    this.port,
    this.database,
    this.username,
    this.password,
    this.sslMode,
    this.basePath,
    this.servingBaseUrl,
  });

  factory PostgresConfigJson.fromJson(Map<String, dynamic> json) =>
      PostgresConfigJson(
        host: json['host'] as String?,
        port: json['port'] as String?,
        database: json['database'] as String?,
        username: json['username'] as String?,
        password: json['password'] as String?,
        sslMode: json['sslMode'] as String?,
        basePath: json['basePath'] as String?,
        servingBaseUrl: json['servingBaseUrl'] as String?,
      );

  final String? host;
  final String? port;
  final String? database;
  final String? username;
  final String? password;
  final String? sslMode;
  final String? basePath;
  final String? servingBaseUrl;

  Map<String, dynamic> toJson() => {
        if (host != null) 'host': host,
        if (port != null) 'port': port,
        if (database != null) 'database': database,
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        if (sslMode != null) 'sslMode': sslMode,
        if (basePath != null) 'basePath': basePath,
        if (servingBaseUrl != null) 'servingBaseUrl': servingBaseUrl,
      };
}

SslMode? _parseSslMode(String? value) {
  switch (value?.toLowerCase()) {
    case 'disable':
      return SslMode.disable;
    case 'require':
      return SslMode.require;
    case 'verify-ca':
    case 'verify-full':
      return SslMode.verifyFull;
    default:
      return null;
  }
}

/// Resolve the Postgres database config (flag > env > json precedence).
PostgresConfig resolvePostgresDatabaseConfig(
  FlutterPatcherConfig config, {
  String? host,
  String? port,
  String? database,
  String? username,
  String? password,
  String? sslMode,
  PostgresClientFactory? clientFactory,
}) {
  final env = Platform.environment;
  final resolvedHost = host ?? env['POSTGRES_HOST'] ?? config.postgres.host;
  final resolvedDatabase =
      database ?? env['POSTGRES_DB'] ?? config.postgres.database;
  final resolvedUser = username ?? env['POSTGRES_USER'] ?? config.postgres.username;
  final resolvedPassword =
      password ?? env['POSTGRES_PASSWORD'] ?? config.postgres.password;
  final resolvedPort = port ??
      env['POSTGRES_PORT'] ??
      config.postgres.port ??
      '5432';
  final resolvedSsl =
      sslMode ?? env['POSTGRES_SSLMODE'] ?? config.postgres.sslMode;

  if (resolvedHost == null || resolvedHost.isEmpty) {
    throw StateError(
      'Postgres host is required. Set --pg-host, POSTGRES_HOST, or '
      '`flutter_patcher config set postgres.host <host>`.',
    );
  }

  return PostgresConfig(
    host: resolvedHost,
    port: int.tryParse(resolvedPort) ?? 5432,
    database: resolvedDatabase ?? 'postgres',
    username: resolvedUser,
    password: resolvedPassword,
    sslMode: _parseSslMode(resolvedSsl),
    clientFactory: clientFactory,
  );
}

/// Resolve the Postgres storage config (shares the DB connection).
PostgresStorageConfig resolvePostgresStorageConfig(
  FlutterPatcherConfig config, {
  String? host,
  String? port,
  String? database,
  String? username,
  String? password,
  String? sslMode,
  String? basePath,
  String? servingBaseUrl,
  PostgresClientFactory? clientFactory,
}) {
  final db = resolvePostgresDatabaseConfig(
    config,
    host: host,
    port: port,
    database: database,
    username: username,
    password: password,
    sslMode: sslMode,
    clientFactory: clientFactory,
  );
  return PostgresStorageConfig(
    db: db,
    basePath: basePath ??
        Platform.environment['POSTGRES_BASE_PATH'] ??
        config.postgres.basePath,
    servingBaseUrl: servingBaseUrl ??
        Platform.environment['POSTGRES_SERVING_BASE_URL'] ??
        config.postgres.servingBaseUrl,
  );
}

// ---------------------------------------------------------------------------
// Cloudflare (D1 + R2) backend config
// ---------------------------------------------------------------------------

/// Cloudflare section of [FlutterPatcherConfig].
class CloudflareConfigJson {
  const CloudflareConfigJson({
    this.accountId,
    this.d1DatabaseId,
    this.apiToken,
    this.r2Bucket,
    this.r2AccessKeyId,
    this.r2SecretAccessKey,
    this.r2BasePath,
  });

  factory CloudflareConfigJson.fromJson(Map<String, dynamic> json) =>
      CloudflareConfigJson(
        accountId: json['accountId'] as String?,
        d1DatabaseId: json['d1DatabaseId'] as String?,
        apiToken: json['apiToken'] as String?,
        r2Bucket: json['r2Bucket'] as String?,
        r2AccessKeyId: json['r2AccessKeyId'] as String?,
        r2SecretAccessKey: json['r2SecretAccessKey'] as String?,
        r2BasePath: json['r2BasePath'] as String?,
      );

  final String? accountId;
  final String? d1DatabaseId;
  final String? apiToken;
  final String? r2Bucket;
  final String? r2AccessKeyId;
  final String? r2SecretAccessKey;
  final String? r2BasePath;

  Map<String, dynamic> toJson() => {
        if (accountId != null) 'accountId': accountId,
        if (d1DatabaseId != null) 'd1DatabaseId': d1DatabaseId,
        if (apiToken != null) 'apiToken': apiToken,
        if (r2Bucket != null) 'r2Bucket': r2Bucket,
        if (r2AccessKeyId != null) 'r2AccessKeyId': r2AccessKeyId,
        if (r2SecretAccessKey != null) 'r2SecretAccessKey': r2SecretAccessKey,
        if (r2BasePath != null) 'r2BasePath': r2BasePath,
      };
}

/// Resolve the Cloudflare D1 database config.
D1DatabaseConfig resolveCloudflareDatabaseConfig(
  FlutterPatcherConfig config, {
  String? accountId,
  String? d1DatabaseId,
  String? apiToken,
  D1ClientFactory? clientFactory,
}) {
  final env = Platform.environment;
  final resolvedAccount =
      accountId ?? env['CLOUDFLARE_ACCOUNT_ID'] ?? config.cloudflare.accountId;
  final resolvedDb = d1DatabaseId ??
      env['CLOUDFLARE_D1_DATABASE_ID'] ??
      config.cloudflare.d1DatabaseId;
  final resolvedToken =
      apiToken ?? env['CLOUDFLARE_API_TOKEN'] ?? config.cloudflare.apiToken;

  if (resolvedAccount == null ||
      resolvedDb == null ||
      resolvedToken == null) {
    throw StateError(
      'Cloudflare requires accountId, d1DatabaseId and apiToken. Set them via '
      'flags, CLOUDFLARE_* env vars, or `flutter_patcher config set cloudflare.*`.',
    );
  }

  return D1DatabaseConfig(
    accountId: resolvedAccount,
    databaseId: resolvedDb,
    cloudflareApiToken: resolvedToken,
    clientFactory: clientFactory,
  );
}

/// Resolve the Cloudflare R2 storage config.
R2S3StorageConfig resolveCloudflareStorageConfig(
  FlutterPatcherConfig config, {
  String? accountId,
  String? bucket,
  String? accessKeyId,
  String? secretAccessKey,
  String? basePath,
  R2S3ClientFactory? clientFactory,
}) {
  final env = Platform.environment;
  final resolvedAccount = accountId ??
      env['CLOUDFLARE_ACCOUNT_ID'] ??
      env['R2_ACCOUNT_ID'] ??
      config.cloudflare.accountId;
  final resolvedBucket =
      bucket ?? env['R2_BUCKET'] ?? config.cloudflare.r2Bucket ?? 'bundles';
  final resolvedKey = accessKeyId ??
      env['R2_ACCESS_KEY_ID'] ??
      config.cloudflare.r2AccessKeyId;
  final resolvedSecret = secretAccessKey ??
      env['R2_SECRET_ACCESS_KEY'] ??
      config.cloudflare.r2SecretAccessKey;

  if (resolvedAccount == null ||
      resolvedKey == null ||
      resolvedSecret == null) {
    throw StateError(
      'Cloudflare R2 requires accountId, accessKeyId and secretAccessKey. Set '
      'them via flags, R2_* env vars, or `flutter_patcher config set cloudflare.*`.',
    );
  }

  return R2S3StorageConfig(
    accountId: resolvedAccount,
    bucketName: resolvedBucket,
    accessKeyId: resolvedKey,
    secretAccessKey: resolvedSecret,
    basePath: basePath ?? env['R2_BASE_PATH'] ?? config.cloudflare.r2BasePath,
    clientFactory: clientFactory,
  );
}

// ---------------------------------------------------------------------------
// AWS (S3 DB + S3 storage) backend config
// ---------------------------------------------------------------------------

/// AWS section of [FlutterPatcherConfig].
class AwsConfigJson {
  const AwsConfigJson({
    this.bucket,
    this.region,
    this.accessKeyId,
    this.secretAccessKey,
    this.endpoint,
    this.basePath,
    this.sessionToken,
  });

  factory AwsConfigJson.fromJson(Map<String, dynamic> json) => AwsConfigJson(
        bucket: json['bucket'] as String?,
        region: json['region'] as String?,
        accessKeyId: json['accessKeyId'] as String?,
        secretAccessKey: json['secretAccessKey'] as String?,
        endpoint: json['endpoint'] as String?,
        basePath: json['basePath'] as String?,
        sessionToken: json['sessionToken'] as String?,
      );

  final String? bucket;
  final String? region;
  final String? accessKeyId;
  final String? secretAccessKey;
  final String? endpoint;
  final String? basePath;
  final String? sessionToken;

  Map<String, dynamic> toJson() => {
        if (bucket != null) 'bucket': bucket,
        if (region != null) 'region': region,
        if (accessKeyId != null) 'accessKeyId': accessKeyId,
        if (secretAccessKey != null) 'secretAccessKey': secretAccessKey,
        if (endpoint != null) 'endpoint': endpoint,
        if (basePath != null) 'basePath': basePath,
        if (sessionToken != null) 'sessionToken': sessionToken,
      };
}

/// Resolve the AWS S3 database config.
S3DatabaseConfig resolveAwsDatabaseConfig(
  FlutterPatcherConfig config, {
  String? bucket,
  String? region,
  String? accessKeyId,
  String? secretAccessKey,
  String? basePath,
  String? endpoint,
  String? sessionToken,
  AwsS3ClientLike Function(S3DatabaseConfig config)? clientFactory,
  AwsCloudFrontClientLike Function(S3DatabaseConfig config)? cloudfrontClientFactory,
}) {
  final env = Platform.environment;
  final resolvedBucket = bucket ?? env['AWS_BUCKET'] ?? config.aws.bucket;
  final resolvedRegion = region ?? env['AWS_REGION'] ?? config.aws.region;
  final resolvedKey =
      accessKeyId ?? env['AWS_ACCESS_KEY_ID'] ?? config.aws.accessKeyId;
  final resolvedSecret =
      secretAccessKey ?? env['AWS_SECRET_ACCESS_KEY'] ?? config.aws.secretAccessKey;

  if (resolvedBucket == null ||
      resolvedRegion == null ||
      resolvedKey == null ||
      resolvedSecret == null) {
    throw StateError(
      'AWS requires bucket, region, accessKeyId and secretAccessKey. Set them '
      'via flags, AWS_* env vars, or `flutter_patcher config set aws.*`.',
    );
  }

  return S3DatabaseConfig(
    bucketName: resolvedBucket,
    region: resolvedRegion,
    accessKeyId: resolvedKey,
    secretAccessKey: resolvedSecret,
    basePath: basePath ?? env['AWS_BASE_PATH'] ?? config.aws.basePath,
    endpoint: endpoint ?? env['AWS_ENDPOINT'] ?? config.aws.endpoint,
    sessionToken: sessionToken ?? env['AWS_SESSION_TOKEN'] ?? config.aws.sessionToken,
    clientFactory: clientFactory ?? defaultAwsS3DatabaseClientFactory,
    cloudfrontClientFactory:
        cloudfrontClientFactory ?? defaultAwsCloudFrontClientFactory,
  );
}

/// Resolve the AWS S3 storage config.
AwsS3StorageConfig resolveAwsStorageConfig(
  FlutterPatcherConfig config, {
  String? bucket,
  String? region,
  String? accessKeyId,
  String? secretAccessKey,
  String? basePath,
  String? endpoint,
  String? sessionToken,
  AwsS3ClientLike Function(AwsS3StorageConfig config)? clientFactory,
}) {
  final env = Platform.environment;
  final resolvedBucket = bucket ?? env['AWS_BUCKET'] ?? config.aws.bucket;
  final resolvedRegion = region ?? env['AWS_REGION'] ?? config.aws.region;
  final resolvedKey =
      accessKeyId ?? env['AWS_ACCESS_KEY_ID'] ?? config.aws.accessKeyId;
  final resolvedSecret =
      secretAccessKey ?? env['AWS_SECRET_ACCESS_KEY'] ?? config.aws.secretAccessKey;

  if (resolvedBucket == null ||
      resolvedRegion == null ||
      resolvedKey == null ||
      resolvedSecret == null) {
    throw StateError(
      'AWS requires bucket, region, accessKeyId and secretAccessKey. Set them '
      'via flags, AWS_* env vars, or `flutter_patcher config set aws.*`.',
    );
  }

  return AwsS3StorageConfig(
    bucketName: resolvedBucket,
    region: resolvedRegion,
    accessKeyId: resolvedKey,
    secretAccessKey: resolvedSecret,
    basePath: basePath ?? env['AWS_BASE_PATH'] ?? config.aws.basePath,
    endpoint: endpoint ?? env['AWS_ENDPOINT'] ?? config.aws.endpoint,
    sessionToken: sessionToken ?? env['AWS_SESSION_TOKEN'] ?? config.aws.sessionToken,
    clientFactory: clientFactory ?? defaultAwsS3ClientFactory,
  );
}

/// Standalone (self-hosted) section of [FlutterPatcherConfig].
class StandaloneConfigJson {
  const StandaloneConfigJson({this.baseUrl});

  factory StandaloneConfigJson.fromJson(Map<String, dynamic> json) =>
      StandaloneConfigJson(baseUrl: json['baseUrl'] as String?);

  final String? baseUrl;

  Map<String, dynamic> toJson() =>
      {if (baseUrl != null) 'baseUrl': baseUrl};
}

/// Resolve the standalone repository (database) config.
StandaloneRepositoryConfig resolveStandaloneDatabaseConfig(
  FlutterPatcherConfig config, {
  String? baseUrl,
  StandaloneClientFactory? clientFactory,
}) {
  final env = Platform.environment;
  final resolvedBaseUrl =
      baseUrl ?? env['STANDALONE_BASE_URL'] ?? config.standalone.baseUrl;
  if (resolvedBaseUrl == null || resolvedBaseUrl.isEmpty) {
    throw StateError(
      'Standalone baseUrl is required. Set --base-url, STANDALONE_BASE_URL, '
      'or `flutter_patcher config set standalone.baseUrl <url>`.',
    );
  }
  return StandaloneRepositoryConfig(
    baseUrl: resolvedBaseUrl,
    clientFactory: clientFactory,
  );
}

/// Resolve the standalone storage config (shares the same self-hosted base).
StandaloneStorageConfig resolveStandaloneStorageConfig(
  FlutterPatcherConfig config, {
  String? baseUrl,
  StandaloneClientFactory? clientFactory,
}) {
  final db = resolveStandaloneDatabaseConfig(
    config,
    baseUrl: baseUrl,
    clientFactory: clientFactory,
  );
  return StandaloneStorageConfig(
    baseUrl: db.baseUrl,
    commonHeaders: db.commonHeaders,
    clientFactory: clientFactory,
  );
}
