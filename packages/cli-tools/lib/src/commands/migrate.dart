import 'dart:convert';
import 'dart:io';

import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

import '../ui/ui.dart';

/// `flutter-ota migrate` — run backend SQL migrations.
class MigrateCommand extends FlutterPatcherCommand {
  MigrateCommand({this.config, this.backendOverride}) {
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption(
      'backend',
      abbr: 'b',
      help: detected != null
          ? 'Backend provider [detected: $detected].'
          : 'Backend provider.',
    );
    argParser.addOption(
      'database-url',
      help: 'Postgres connection string (or DATABASE_URL env).',
    );
    argParser.addOption(
      'management-key',
      help:
          'Supabase Management API key (or SUPABASE_MANAGEMENT_KEY env) — '
          'runs migrations without a separate Postgres connection.',
    );
    argParser.addOption(
      'migrations-dir',
      help: 'Directory of *.sql migration files (ordered by name).',
    );
    argParser.addOption(
      'account-id',
      help: 'Cloudflare account ID (or CLOUDFLARE_ACCOUNT_ID env).',
    );
    argParser.addOption(
      'api-token',
      help: 'Cloudflare API token (or CLOUDFLARE_API_TOKEN env).',
    );
    argParser.addOption(
      'd1-database-id',
      help: 'Cloudflare D1 database ID (or CLOUDFLARE_D1_DATABASE_ID env).',
    );
    argParser.addOption(
      'r2-bucket',
      help: 'Cloudflare R2 bucket name (or R2_BUCKET env, default: bundles).',
    );
    argParser.addOption(
      'pocketbase-url',
      help: 'PocketBase URL (or POCKETBASE_URL env).',
    );
    argParser.addOption(
      'pocketbase-admin-email',
      help: 'PocketBase admin email (or POCKETBASE_ADMIN_EMAIL env).',
    );
    argParser.addOption(
      'pocketbase-admin-password',
      help: 'PocketBase admin password (or POCKETBASE_ADMIN_PASSWORD env).',
    );
    argParser.addFlag(
      'dry-run',
      abbr: 'd',
      help: 'Print migrations instead of applying them.',
    );
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Run SQL migrations against the backend database (Supabase, Postgres, Cloudflare, AWS, PocketBase).';

  String defaultMigrationsDir(String provider) {
    final sub = switch (provider) {
      'supabase' => 'supabase',
      'postgres' => 'postgres',
      'cloudflare' => 'cloudflare',
      'aws' => 'aws',
      _ => 'supabase',
    };
    return p.join(p.dirname(Platform.script.path), '..', 'migrations', sub);
  }

  List<File> _listMigrations(String dir) {
    final migrationsDir = Directory(dir);
    if (!migrationsDir.existsSync()) {
      throw StateError('Migrations directory not found: $dir');
    }
    final files =
        migrationsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) {
      throw StateError('No *.sql files in $dir');
    }
    return files;
  }

  List<String> _splitStatements(String sql) {
    return sql
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('--'))
        .toList();
  }

  @override
  Future<int> run() => runGuarded(() async {
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final provider =
        argResults!['backend'] as String? ?? cfg?.provider ?? 'supabase';

    if (provider == 'aws') {
      banner('migrate · aws');
      step(
        'AWS stores bundle metadata as JSON in S3 — no SQL migrations needed.',
      );
      step(
        'The S3 bucket and object prefix are created automatically on first deploy.',
      );
      step('No action required. Run `flutter-ota deploy` to get started.');
      return;
    }

    if (provider == 'pocketbase') {
      final pbUrl =
          argResults!['pocketbase-url'] as String? ??
          Platform.environment['POCKETBASE_URL'] ??
          cfg?.pocketbase.url;
      final pbAdmin =
          argResults!['pocketbase-admin-email'] as String? ??
          Platform.environment['POCKETBASE_ADMIN_EMAIL'] ??
          cfg?.pocketbase.adminEmail;
      final pbPass =
          argResults!['pocketbase-admin-password'] as String? ??
          Platform.environment['POCKETBASE_ADMIN_PASSWORD'] ??
          cfg?.pocketbase.adminPassword;
      if (pbUrl == null || pbUrl.isEmpty) {
        throw StateError(
          'PocketBase requires a URL. Set POCKETBASE_URL env var, '
          'or `flutter-ota init pocketbase`.',
        );
      }
      banner('migrate · pocketbase');
      final installer = PocketBaseSchemaInstaller(
        url: pbUrl,
        adminEmail: pbAdmin ?? '',
        adminPassword: pbPass ?? '',
      );
      final res = await installer.install();
      final steps = Steps('migrate');
      if (res.created.isNotEmpty) {
        steps.success('Created: ${res.created.join(', ')}');
      }
      if (res.skipped.isNotEmpty) {
        steps.success('Already present: ${res.skipped.join(', ')}');
      }
      steps.summary();
      return;
    }

    final dir =
        argResults!['migrations-dir'] as String? ??
        defaultMigrationsDir(provider);
    final files = _listMigrations(dir);

    if (argResults!['dry-run'] as bool) {
      banner('migrate · dry-run');
      for (final f in files) {
        stdout.writeln('--- ${p.basename(f.path)} ---');
        stdout.writeln(f.readAsStringSync());
      }
      return;
    }

    if (provider == 'cloudflare') {
      final cfCfg =
          cfg ??
          FlutterPatcherConfig(
            provider: 'cloudflare',
            supabase: const SupabaseConfigJson(),
            cloudflare: const CloudflareConfigJson(),
          );
      final accountId =
          argResults!['account-id'] as String? ??
          Platform.environment['CLOUDFLARE_ACCOUNT_ID'] ??
          cfCfg.cloudflare.accountId;
      final apiToken =
          argResults!['api-token'] as String? ??
          Platform.environment['CLOUDFLARE_API_TOKEN'] ??
          cfCfg.cloudflare.apiToken;
      final dbId =
          argResults!['d1-database-id'] as String? ??
          Platform.environment['CLOUDFLARE_D1_DATABASE_ID'] ??
          cfCfg.cloudflare.d1DatabaseId;
      final r2Bucket =
          argResults!['r2-bucket'] as String? ??
          Platform.environment['R2_BUCKET'] ??
          cfCfg.cloudflare.r2Bucket ??
          'bundles';

      if (accountId == null || apiToken == null) {
        throw StateError(
          'Cloudflare requires accountId and apiToken. Set them via '
          '--account-id/--api-token, CLOUDFLARE_* env vars, or '
          '`flutter-ota init cloudflare`.',
        );
      }
      await _runCloudflareMigration(
        accountId: accountId,
        apiToken: apiToken,
        databaseId: dbId,
        r2Bucket: r2Bucket,
        files: files,
      );
      return;
    }

    if (provider == 'supabase') {
      final sbCfg =
          cfg ??
          FlutterPatcherConfig(
            provider: 'supabase',
            supabase: const SupabaseConfigJson(),
          );
      final mgmtKey =
          argResults!['management-key'] as String? ??
          Platform.environment['SUPABASE_MANAGEMENT_KEY'] ??
          sbCfg.supabase.managementKey;
      final pgUrl =
          argResults!['database-url'] as String? ??
          Platform.environment['DATABASE_URL'] ??
          sbCfg.supabase.databaseUrl;
      if (mgmtKey != null && mgmtKey.isNotEmpty) {
        await _runViaManagementApi(mgmtKey, files);
        return;
      }
      if (pgUrl != null && pgUrl.isNotEmpty) {
        await _runViaPostgres(pgUrl, files);
        return;
      }
      throw StateError(
        'For the supabase backend, provide either:\n'
        '  · --management-key (or SUPABASE_MANAGEMENT_KEY, or set it via '
        '`flutter-ota init`) — a Supabase Management API key, OR\n'
        '  · --database-url (or DATABASE_URL, or set it via `init`) — a '
        'Postgres connection string.',
      );
    }

    if (provider == 'postgres') {
      final pgUrl =
          argResults!['database-url'] as String? ??
          Platform.environment['DATABASE_URL'];
      if (pgUrl == null || pgUrl.isEmpty) {
        throw StateError(
          'For the postgres backend, provide --database-url or set DATABASE_URL.',
        );
      }
      await _runViaPostgres(pgUrl, files);
      return;
    }

    throw StateError('Unknown backend provider: "$provider".');
  });

  Future<void> _runViaManagementApi(String mgmtKey, List<File> files) async {
    final cfg = resolveSupabaseConfig(
      loadConfig() ??
          FlutterPatcherConfig(
            provider: 'supabase',
            supabase: SupabaseConfigJson(),
          ),
    );
    final ref = Uri.parse(cfg.supabaseUrl).host.split('.').first;
    final endpoint = 'https://api.supabase.com/v1/projects/$ref/database/query';
    banner('migrate · supabase (management api)');
    final steps = Steps('migrate');
    for (final file in files) {
      final sw = Stopwatch()..start();
      final sql = file.readAsStringSync();
      final res = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $mgmtKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'query': sql}),
      );
      sw.stop();
      if (res.statusCode >= 400) {
        steps.fail('${p.basename(file.path)} (${res.statusCode}): ${res.body}');
      } else {
        final ms = sw.elapsedMilliseconds;
        final time = ms >= 1000
            ? '${(ms / 1000).toStringAsFixed(1)}s'
            : '${ms}ms';
        steps.success('Applied ${p.basename(file.path)} in $time');
      }
    }
    await _ensureSupabaseBucket(steps);
    steps.summary();
    if (steps.hasErrors) {
      throw StateError('One or more migrations failed.');
    }
  }

  Future<void> _ensureSupabaseBucket(Steps steps) async {
    final storage = resolveSupabaseStorageConfig(
      loadConfig() ??
          FlutterPatcherConfig(
            provider: 'supabase',
            supabase: SupabaseConfigJson(),
          ),
    );
    if (storage.supabaseServiceRoleKey == null) {
      steps.skip(
        'Skipped storage bucket creation — set supabase.serviceRoleKey',
      );
      return;
    }
    final sw = Stopwatch()..start();
    final res = await http.post(
      Uri.parse('${storage.supabaseUrl}/storage/v1/bucket'),
      headers: {
        'Authorization': 'Bearer ${storage.supabaseServiceRoleKey}',
        'apikey': storage.supabaseServiceRoleKey!,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': storage.bucketName, 'public': true}),
    );
    sw.stop();
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final msg = (body['message'] ?? body['error'] ?? '').toString();
      if (!msg.contains('already exists') && res.statusCode != 409) {
        steps.fail('Could not create bucket "${storage.bucketName}": $msg');
        return;
      }
    }
    final ms = sw.elapsedMilliseconds;
    final time = ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';
    steps.success('Ensured storage bucket "${storage.bucketName}" in $time');
  }

  Future<void> _runViaPostgres(String url, List<File> files) async {
    final uri = Uri.parse(url);
    final endpoint = Endpoint(
      host: uri.host,
      port: uri.port == 0 ? 5432 : uri.port,
      database: uri.path.isEmpty ? 'postgres' : uri.path.substring(1),
      username: uri.userInfo.isEmpty ? null : uri.userInfo.split(':').first,
      password: uri.userInfo.contains(':')
          ? uri.userInfo.split(':').last
          : null,
    );
    banner('migrate · postgres');
    final steps = Steps('migrate');
    final conn = await Connection.open(
      endpoint,
      settings: ConnectionSettings(sslMode: SslMode.disable),
    );
    try {
      await conn.execute(
        'CREATE TABLE IF NOT EXISTS _flutter_ota_kit_migrations '
        '(name text primary key, applied_at timestamptz default now())',
        queryMode: QueryMode.simple,
      );
      for (final file in files) {
        final name = p.basename(file.path);
        final escaped = name.replaceAll("'", "''");
        final existing = await conn.execute(
          "SELECT 1 FROM _flutter_ota_kit_migrations WHERE name = '$escaped'",
          queryMode: QueryMode.simple,
        );
        if (existing.isNotEmpty) {
          steps.skip('Skipped $name (already applied)');
          continue;
        }
        final sw = Stopwatch()..start();
        for (final stmt in _splitStatements(file.readAsStringSync())) {
          await conn.execute(stmt, queryMode: QueryMode.simple);
        }
        await conn.execute(
          "INSERT INTO _flutter_ota_kit_migrations(name) VALUES ('$escaped')",
          queryMode: QueryMode.simple,
        );
        sw.stop();
        final ms = sw.elapsedMilliseconds;
        final time = ms >= 1000
            ? '${(ms / 1000).toStringAsFixed(1)}s'
            : '${ms}ms';
        steps.success('Applied $name in $time');
      }
    } finally {
      await conn.close();
    }
    steps.summary();
  }

  /// Auto-provision Cloudflare backend: create D1 database, run SQL, create R2.
  ///
  /// Called from `init` to match Supabase's fully-automated flow.
  static Future<void> runCloudflareMigration({
    required String accountId,
    required String apiToken,
    String? databaseId,
    String? r2Bucket,
  }) async {
    final sub = 'cloudflare';
    final dir = p.join(
      p.dirname(Platform.script.path),
      '..',
      'migrations',
      sub,
    );
    final migrationsDir = Directory(dir);
    if (!migrationsDir.existsSync()) {
      throw StateError('Migrations directory not found: $dir');
    }
    final files =
        migrationsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) {
      throw StateError('No *.sql files in $dir');
    }
    await _runCloudflareMigration(
      accountId: accountId,
      apiToken: apiToken,
      databaseId: databaseId,
      r2Bucket: r2Bucket ?? 'bundles',
      files: files,
    );
  }

  static Future<void> _runCloudflareMigration({
    required String accountId,
    required String apiToken,
    required String? databaseId,
    required String r2Bucket,
    required List<File> files,
  }) async {
    final headers = {
      'Authorization': 'Bearer $apiToken',
      'Content-Type': 'application/json',
    };
    final baseUrl = 'https://api.cloudflare.com/client/v4';

    banner('migrate · cloudflare');
    final steps = Steps('migrate');

    // --- D1 database ---
    var dbId = databaseId;
    if (dbId == null || dbId.isEmpty) {
      // Create a new D1 database
      final sw = Stopwatch()..start();
      final res = await http.post(
        Uri.parse('$baseUrl/accounts/$accountId/d1/database'),
        headers: headers,
        body: jsonEncode({'name': 'flutter-ota-kit'}),
      );
      sw.stop();
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400 || body['success'] != true) {
        final errors = body['errors'] as List? ?? [];
        final msg = errors.isNotEmpty ? errors.first['message'] : res.body;
        steps.fail('Could not create D1 database: $msg');
        steps.summary();
        return;
      }
      dbId = body['result']?['uuid'] as String?;
      if (dbId == null || dbId.isEmpty) {
        steps.fail('D1 database created but no UUID returned');
        steps.summary();
        return;
      }
      final ms = sw.elapsedMilliseconds;
      final time = ms >= 1000
          ? '${(ms / 1000).toStringAsFixed(1)}s'
          : '${ms}ms';
      steps.success('Created D1 database ($dbId) in $time');
    } else {
      steps.success('Using existing D1 database ($dbId)');
    }

    // --- Run SQL migrations against D1 ---
    for (final file in files) {
      final sw = Stopwatch()..start();
      final sql = file.readAsStringSync();
      final res = await http.post(
        Uri.parse('$baseUrl/accounts/$accountId/d1/database/$dbId/query'),
        headers: headers,
        body: jsonEncode({'sql': sql}),
      );
      sw.stop();
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400 || body['success'] != true) {
        final errors = body['errors'] as List? ?? [];
        final msg = errors.isNotEmpty ? errors.first['message'] : res.body;
        steps.fail('${p.basename(file.path)} ($res.statusCode): $msg');
      } else {
        final ms = sw.elapsedMilliseconds;
        final time = ms >= 1000
            ? '${(ms / 1000).toStringAsFixed(1)}s'
            : '${ms}ms';
        steps.success('Applied ${p.basename(file.path)} in $time');
      }
    }

    // --- R2 bucket ---
    final sw = Stopwatch()..start();
    final r2Res = await http.put(
      Uri.parse('$baseUrl/accounts/$accountId/s3/buckets/$r2Bucket'),
      headers: headers,
    );
    sw.stop();
    final r2Body = jsonDecode(r2Res.body) as Map<String, dynamic>;
    if (r2Res.statusCode >= 400 || r2Body['success'] != true) {
      final errors = r2Body['errors'] as List? ?? [];
      final msg = errors.isNotEmpty ? errors.first['message'] : r2Res.body;
      // Bucket already exists is not an error
      if (!msg.toLowerCase().contains('already exists') &&
          r2Res.statusCode != 409) {
        steps.fail('Could not create R2 bucket "$r2Bucket": $msg');
      } else {
        final ms = sw.elapsedMilliseconds;
        final time = ms >= 1000
            ? '${(ms / 1000).toStringAsFixed(1)}s'
            : '${ms}ms';
        steps.success('Ensured R2 bucket "$r2Bucket" in $time');
      }
    } else {
      final ms = sw.elapsedMilliseconds;
      final time = ms >= 1000
          ? '${(ms / 1000).toStringAsFixed(1)}s'
          : '${ms}ms';
      steps.success('Created R2 bucket "$r2Bucket" in $time');
    }

    steps.summary();
    if (steps.hasErrors) {
      throw StateError('One or more migrations failed.');
    }
  }
}
