import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_patcher_cli/flutter_patcher_cli.dart';

import '../ui/ui.dart';

/// `flutter_patcher init` — scaffold a project config file.
///
/// Prompts (interactively, when attached to a terminal) for the credentials the
/// **selected** backend provider needs, defaulting each field to its
/// corresponding environment variable so CI runs can be non-interactive. The
/// result is saved as `.flutter_patcher.json` (cwd) or the global config when
/// `--global` is passed.
class InitCommand extends FlutterPatcherCommand {
  InitCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Scaffold a .flutter_patcher.json config for the current project.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('provider',
        abbr: 'p', defaultsTo: 'supabase', help: 'Backend provider.')
    ..addOption('channel', defaultsTo: 'production', help: 'Default channel.')
    ..addOption('platform', defaultsTo: 'android', help: 'Default platform.')
    ..addOption('source', defaultsTo: './dist', help: 'Default deploy source.')
    ..addFlag('global', help: 'Write to the global ~/.flutter_patcher config.')
    ..addFlag('force', abbr: 'f', help: 'Overwrite an existing config.');

  String? _p(String label, String? current) {
    if (!stdin.hasTerminal) return current;
    final hint = current != null && current.isNotEmpty ? ' [$current]' : '';
    stdout.write('$label$hint: ');
    final line = stdin.readLineSync();
    final trimmed = (line ?? '').trim();
    return trimmed.isEmpty ? current : trimmed;
  }

  /// Backends `init` can scaffold, in display order.
  static const List<String> _providers = [
    'supabase',
    'standalone',
    'postgres',
    'cloudflare',
    'aws',
  ];

  /// Interactive backend picker. Returns the chosen provider, defaulting to
  /// [requested] when the user just presses enter.
  String _chooseProvider(String requested) {
    stdout.writeln(cyan('Select a backend provider:'));
    for (var i = 0; i < _providers.length; i++) {
      final marker = _providers[i] == requested ? '*' : ' ';
      stdout.writeln('  ${dim(marker)} ${i + 1}. ${_providers[i]}');
    }
    stdout.write('Provider ${dim('[1]')}: ');
    final line = stdin.readLineSync()?.trim();
    if (line == null || line.isEmpty) return requested;
    final n = int.tryParse(line);
    if (n != null && n >= 1 && n <= _providers.length) {
      return _providers[n - 1];
    }
    return line;
  }

  @override
  Future<int> run() => runGuarded(() async {
        final file = argResults!['global'] as bool
            ? configCandidates().last
            : configCandidates().first;
        if (file.existsSync() && !(argResults!['force'] as bool)) {
          throw PackException(
            'Config already exists at ${file.path}. Use --force to overwrite.',
            64,
          );
        }

        final requested = argResults!['provider'] as String;
        final provider =
            stdin.hasTerminal ? _chooseProvider(requested) : requested;
        if (!_providers.contains(provider)) {
          throw PackException(
            'Unknown provider "$provider". Choose one of: '
            '${_providers.join(', ')}.',
            64,
          );
        }
        final channel = argResults!['channel'] as String? ?? 'production';
        final platform = argResults!['platform'] as String? ?? 'android';
        final source = argResults!['source'] as String? ?? './dist';
        final env = Platform.environment;

        banner('init');

        late FlutterPatcherConfig cfg;
        switch (provider) {
          case 'postgres':
            cfg = FlutterPatcherConfig(
              provider: provider,
              channel: channel,
              platform: platform,
              source: source,
              supabase: const SupabaseConfigJson(),
              postgres: PostgresConfigJson(
                host: _p('Postgres host', env['POSTGRES_HOST']),
                port: _p('Postgres port', env['POSTGRES_PORT'] ?? '5432'),
                database: _p('Postgres database', env['POSTGRES_DB'] ?? 'postgres'),
                username: _p('Postgres username', env['POSTGRES_USER']),
                password: _p('Postgres password', env['POSTGRES_PASSWORD']),
                sslMode: _p('Postgres sslmode', env['POSTGRES_SSLMODE']),
                basePath: _p('Storage base path', env['POSTGRES_BASE_PATH']),
                servingBaseUrl:
                    _p('Serving base url', env['POSTGRES_SERVING_BASE_URL']),
              ),
            );
          case 'cloudflare':
            cfg = FlutterPatcherConfig(
              provider: provider,
              channel: channel,
              platform: platform,
              source: source,
              supabase: const SupabaseConfigJson(),
              cloudflare: CloudflareConfigJson(
                accountId: _p('Cloudflare account id', env['CLOUDFLARE_ACCOUNT_ID']),
                d1DatabaseId:
                    _p('Cloudflare D1 database id', env['CLOUDFLARE_D1_DATABASE_ID']),
                apiToken: _p('Cloudflare API token', env['CLOUDFLARE_API_TOKEN']),
                r2Bucket:
                    _p('R2 bucket', env['R2_BUCKET'] ?? 'bundles'),
                r2AccessKeyId: _p('R2 access key id', env['R2_ACCESS_KEY_ID']),
                r2SecretAccessKey:
                    _p('R2 secret access key', env['R2_SECRET_ACCESS_KEY']),
                r2BasePath: _p('R2 base path', env['R2_BASE_PATH']),
              ),
            );
          case 'aws':
            cfg = FlutterPatcherConfig(
              provider: provider,
              channel: channel,
              platform: platform,
              source: source,
              supabase: const SupabaseConfigJson(),
              aws: AwsConfigJson(
                bucket: _p('AWS bucket', env['AWS_BUCKET']),
                region: _p('AWS region', env['AWS_REGION']),
                accessKeyId: _p('AWS access key id', env['AWS_ACCESS_KEY_ID']),
                secretAccessKey:
                    _p('AWS secret access key', env['AWS_SECRET_ACCESS_KEY']),
                endpoint: _p('AWS endpoint', env['AWS_ENDPOINT']),
                basePath: _p('AWS base path', env['AWS_BASE_PATH']),
                sessionToken: _p('AWS session token', env['AWS_SESSION_TOKEN']),
              ),
            );
          case 'standalone':
            cfg = FlutterPatcherConfig(
              provider: provider,
              channel: channel,
              platform: platform,
              source: source,
              supabase: const SupabaseConfigJson(),
              standalone: StandaloneConfigJson(
                baseUrl: _p('Standalone base url', env['STANDALONE_BASE_URL']),
              ),
            );
          case 'supabase':
          default:
            cfg = FlutterPatcherConfig(
              provider: 'supabase',
              channel: channel,
              platform: platform,
              source: source,
              supabase: SupabaseConfigJson(
                url: _p('Supabase URL', env['SUPABASE_URL']),
                serviceRoleKey:
                    _p('Supabase service role key', env['SUPABASE_SERVICE_ROLE_KEY']),
                anonKey: _p('Supabase anon key', env['SUPABASE_ANON_KEY']),
                bucket: _p('Storage bucket', env['SUPABASE_BUCKET'] ?? 'bundles'),
                basePath: _p('Storage base path', env['SUPABASE_BASE_PATH']),
                managementKey: _p(
                    'Supabase Management API key (optional, used by `migrate`)',
                    env['SUPABASE_MANAGEMENT_KEY']),
                databaseUrl: _p(
                    'Postgres DATABASE_URL (optional, used by `migrate`)',
                    env['SUPABASE_DATABASE_URL']),
              ),
            );
        }

        saveConfig(cfg, global: argResults!['global'] as bool);
        step('Wrote ${file.path}');
        stdout.writeln(
          '  ${yellow('⚠')} Secrets are stored in plaintext. Restrict file '
          'permissions and use a secrets manager in production.',
        );
      });
}
