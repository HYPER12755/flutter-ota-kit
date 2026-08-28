import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

import '../cli_base.dart';

/// `flutter_patcher migrate` — run backend SQL migrations.
class MigrateCommand extends Command<int> {
  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Run SQL migrations against the backend database (Supabase Postgres).';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Backend provider.')
    ..addOption('database-url',
        help: 'Postgres connection string (or DATABASE_URL env).')
    ..addOption('migrations-dir',
        help: 'Directory of *.sql migration files (ordered by name).')
    ..addFlag('dry-run', help: 'Print migrations instead of applying them.');

  /// Default migrations dir lives next to the CLI entrypoint; the backend
  /// selects which dialect's migrations are used (cloudflare = D1 SQLite).
  String defaultMigrationsDir(String provider) {
    final sub = switch (provider) {
      'cloudflare' => 'cloudflare',
      _ => 'supabase',
    };
    return p.join(p.dirname(Platform.script.path), '..', 'migrations', sub);
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
        final dir = argResults!['migrations-dir'] as String? ??
            defaultMigrationsDir(provider);
        final migrationsDir = Directory(dir);
        if (!migrationsDir.existsSync()) {
          throw StateError('Migrations directory not found: $dir');
        }
        final files = migrationsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        if (files.isEmpty) {
          throw StateError('No *.sql files in $dir');
        }

        if (argResults!['dry-run'] as bool) {
          for (final f in files) {
            stdout.writeln('--- ${p.basename(f.path)} ---');
            stdout.writeln(f.readAsStringSync());
          }
          return;
        }

        final url = argResults!['database-url'] as String? ??
            Platform.environment['DATABASE_URL'];
        if (provider == 'cloudflare' || provider == 'aws') {
          stdout.writeln(
            'Migrations for "$provider" are applied via its platform tooling '
            '(e.g. `wrangler d1 execute` for cloudflare, or the AWS console for '
            'S3/DynamoDB). The SQL above shows the intended schema.',
          );
          return;
        }
        if (url == null || url.isEmpty) {
          throw StateError('Provide --database-url or set DATABASE_URL.');
        }

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
        final conn = await Connection.open(
          endpoint,
          settings: ConnectionSettings(sslMode: SslMode.disable),
        );
        try {
          await conn.execute(
            'CREATE TABLE IF NOT EXISTS _flutter_patcher_migrations '
            '(name text primary key, applied_at timestamptz default now())',
            queryMode: QueryMode.simple,
          );
          for (final file in files) {
            final name = p.basename(file.path);
            final escaped = name.replaceAll("'", "''");
            final existing = await conn.execute(
              "SELECT 1 FROM _flutter_patcher_migrations WHERE name = '$escaped'",
              queryMode: QueryMode.simple,
            );
            if (existing.isNotEmpty) {
              stdout.writeln('skip    $name (already applied)');
              continue;
            }
            final statements = _splitStatements(file.readAsStringSync());
            for (final stmt in statements) {
              await conn.execute(stmt, queryMode: QueryMode.simple);
            }
            await conn.execute(
              "INSERT INTO _flutter_patcher_migrations(name) VALUES ('$escaped')",
              queryMode: QueryMode.simple,
            );
            stdout.writeln('applied $name');
          }
        } finally {
          await conn.close();
        }
      });
}
