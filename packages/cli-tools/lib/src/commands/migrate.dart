import 'dart:convert';
import 'dart:io';

import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

import '../ui/ui.dart';

/// `flutter-ota migrate` — run backend SQL migrations.
class MigrateCommand extends FlutterPatcherCommand {
  MigrateCommand() {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
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
    argParser.addFlag(
      'dry-run',
      abbr: 'd',
      help: 'Print migrations instead of applying them.',
    );
  }

  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Run SQL migrations against the backend database (Supabase Postgres).';

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
    final provider = argResults!['backend'] as String? ?? 'supabase';

    if (provider == 'aws') {
      final dir =
          argResults!['migrations-dir'] as String? ??
          defaultMigrationsDir(provider);
      banner('migrate');
      box('migrate', [
        'Migrations for "$provider" do not run through this command:',
        '  · aws  → S3 blob store, no relational SQL (see $dir/README.md)',
        '',
        'See the README under $dir for the intended setup.',
      ]);
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
      banner('migrate');
      box('migrate', [
        'Cloudflare (D1 SQLite) migrations run via `wrangler d1 execute`:',
        '  wrangler d1 execute <DB> --file=$dir/0001_hot-updater_init.sql',
        '  (apply each *.sql under $dir in filename order)',
        '',
        'The SQL files under $dir show the intended D1 schema.',
      ]);
      return;
    }

    if (provider == 'supabase') {
      final cfg =
          loadConfig() ??
          FlutterPatcherConfig(
            provider: 'supabase',
            supabase: const SupabaseConfigJson(),
          );
      final mgmtKey =
          argResults!['management-key'] as String? ??
          Platform.environment['SUPABASE_MANAGEMENT_KEY'] ??
          cfg.supabase.managementKey;
      final pgUrl =
          argResults!['database-url'] as String? ??
          Platform.environment['DATABASE_URL'] ??
          cfg.supabase.databaseUrl;
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
        steps.fail(
          '${p.basename(file.path)} (${res.statusCode}): ${res.body}',
        );
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
    final time = ms >= 1000
        ? '${(ms / 1000).toStringAsFixed(1)}s'
        : '${ms}ms';
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
}
