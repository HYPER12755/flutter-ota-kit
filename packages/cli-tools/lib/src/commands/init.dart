import 'dart:io';

import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';

import '../ui/ui.dart';

/// `flutter-ota init <backend>` — scaffold a Flutter project for OTA updates.
///
/// Beyond writing the `.flutter_ota_kit/config.json` (so every other `flutter_ota_kit` command
/// knows the backend), it also drops the files a host app actually needs:
///
///   * adds the `flutter_ota_kit` pub dependency to `pubspec.yaml`,
///   * adds the `INTERNET` permission to the Android manifest (the auto-init
///     `ContentProvider` is merged in automatically by the plugin),
///   * generates `lib/flutter_ota_kit_setup.dart` that wires the selected backend
///     and enables zero-click forced updates.
///
/// All CLI working state is stored under `.flutter_ota_kit/`.
class InitCommand extends FlutterPatcherCommand {
  InitCommand({this.config, this.backendOverride}) {
    argParser.addOption(
      'provider',
      abbr: 'p',
      defaultsTo: 'supabase',
      help:
          'Backend provider (also accepted as the first positional argument).',
    );
    argParser.addOption(
      'channel',
      abbr: 'c',
      defaultsTo: 'production',
      help: 'Default channel.',
    );
    argParser.addOption('platform', defaultsTo: 'android', help: 'Default platform.');
    argParser.addOption(
      'source',
      abbr: 's',
      defaultsTo: './dist',
      help: 'Default deploy source.',
    );
    argParser.addFlag(
      'global',
      help: 'Write to the global ~/.flutter_ota_kit config (no scaffolding).',
    );
    argParser.addFlag('force', abbr: 'f', help: 'Overwrite an existing config.');
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Scaffold flutter-ota integration files + .flutter_ota_kit config for the current '
      'Flutter project. Usage: flutter-ota init <supabase|postgres|cloudflare|aws|pocketbase>';

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
    'postgres',
    'cloudflare',
    'aws',
    'pocketbase',
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
    // A positional backend (`flutter-ota init supabase`) takes precedence
    // over the --provider flag.
    final positional = argResults!.rest;
    final requested = positional.isNotEmpty
        ? positional.first
        : (argResults!['provider'] as String);
    final provider = stdin.hasTerminal ? _chooseProvider(requested) : requested;
    if (!_providers.contains(provider)) {
      throw PackException(
        'Unknown provider "$provider". Choose one of: '
        '${_providers.join(', ')}.',
        64,
      );
    }

    final global = argResults!['global'] as bool;
    final file = global ? configCandidates().last : configCandidates().first;
    if (file.existsSync() && !(argResults!['force'] as bool)) {
      throw PackException(
        'Config already exists at ${file.path}. Use --force to overwrite.',
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
            servingBaseUrl: _p(
              'Serving base url',
              env['POSTGRES_SERVING_BASE_URL'],
            ),
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
            accountId: _p(
              'Cloudflare account id',
              env['CLOUDFLARE_ACCOUNT_ID'],
            ),
            d1DatabaseId: _p(
              'Cloudflare D1 database id',
              env['CLOUDFLARE_D1_DATABASE_ID'],
            ),
            apiToken: _p('Cloudflare API token', env['CLOUDFLARE_API_TOKEN']),
            r2Bucket: _p('R2 bucket', env['R2_BUCKET'] ?? 'bundles'),
            r2AccessKeyId: _p('R2 access key id', env['R2_ACCESS_KEY_ID']),
            r2SecretAccessKey: _p(
              'R2 secret access key',
              env['R2_SECRET_ACCESS_KEY'],
            ),
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
            secretAccessKey: _p(
              'AWS secret access key',
              env['AWS_SECRET_ACCESS_KEY'],
            ),
            endpoint: _p('AWS endpoint', env['AWS_ENDPOINT']),
            basePath: _p('AWS base path', env['AWS_BASE_PATH']),
            sessionToken: _p('AWS session token', env['AWS_SESSION_TOKEN']),
          ),
        );
      case 'pocketbase':
        cfg = FlutterPatcherConfig(
          provider: provider,
          channel: channel,
          platform: platform,
          source: source,
          supabase: const SupabaseConfigJson(),
          pocketbase: PocketBaseConfigJson(
            url: _p('PocketBase URL', env['POCKETBASE_URL']),
            adminEmail: _p(
              'PocketBase admin email',
              env['POCKETBASE_ADMIN_EMAIL'],
            ),
            adminPassword: _p(
              'PocketBase admin password',
              env['POCKETBASE_ADMIN_PASSWORD'],
            ),
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
            serviceRoleKey: _p(
              'Supabase service role key',
              env['SUPABASE_SERVICE_ROLE_KEY'],
            ),
            anonKey: _p(
              'Supabase publishable key',
              env['SUPABASE_PUBLISHABLE_KEY'],
            ),
            bucket: _p('Storage bucket', env['SUPABASE_BUCKET'] ?? 'bundles'),
            basePath: _p('Storage base path', env['SUPABASE_BASE_PATH']),
            managementKey: _p(
              'Supabase Management API key (optional, used by `migrate`)',
              env['SUPABASE_MANAGEMENT_KEY'],
            ),
            databaseUrl: _p(
              'Postgres DATABASE_URL (optional, used by `migrate`)',
              env['SUPABASE_DATABASE_URL'],
            ),
          ),
        );
    }

    saveConfig(cfg, global: global);
    step('Wrote ${file.path}');

    if (global) {
      stdout.writeln(
        '  ${yellow('⚠')} Secrets are stored in plaintext under ~/.flutter_ota_kit. '
        'Restrict permissions and use a secrets manager in production.',
      );
      return;
    }

    // Scaffold the host project integration files.
    await _scaffoldProject(cfg, provider);

    stdout.writeln();
    stdout.writeln(cyan('Next steps:'));
    stdout.writeln('  1. ${dim('flutter pub get')}');
    stdout.writeln(
      '  2. In lib/main.dart call ${green('await setupFlutterOta();')} '
      'right after WidgetsFlutterBinding.ensureInitialized() (before runApp).',
    );
    stdout.writeln(
      '     A `.env` scaffold was written — put secrets there, then build with '
      '`--dart-define-from-file=.env` (environment overrides config).',
    );
    if (provider == 'supabase') {
      stdout.writeln(
        '  3. Provision the backend once: ${dim('flutter-ota migrate supabase')}',
      );
    } else if (provider == 'postgres') {
      stdout.writeln(
        '  3. Provision the backend: ${dim('flutter-ota migrate postgres')}',
      );
    } else if (provider == 'pocketbase') {
      stdout.writeln(
        '  3. Install PocketBase + provision the schema: '
        '${dim('flutter-ota pocketbase install')} then '
        '${dim('flutter-ota pocketbase serve')}.',
      );
    }
    stdout.writeln(
      '  4. Build a patch: ${dim('flutter-ota build --name 1.0.1')} '
      'then ${dim('flutter-ota deploy')}',
    );
  });

  /// Generate the integration files (pubspec dep, manifest permission, setup dart
  /// file, .gitignore entry) inside the current directory.
  Future<void> _scaffoldProject(
    FlutterPatcherConfig cfg,
    String provider,
  ) async {
    _addPubDependency();
    _addInternetPermission();
    await _writeSetupFile(cfg, provider);
    _writeEnvFile(cfg, provider);
    _ensureGitignore();
  }

  void _addPubDependency() {
    final pubspec = File('pubspec.yaml');
    if (!pubspec.existsSync()) {
      stdout.writeln(
        yellow('  ⚠ pubspec.yaml not found; skipping dependency injection.'),
      );
      return;
    }
    var content = pubspec.readAsStringSync();
    if (content.contains(RegExp(r'^\s*flutter_ota_kit\s*:', multiLine: true))) {
      step('pubspec.yaml already references flutter_ota_kit');
      return;
    }
    const dep = '  flutter_ota_kit: ^0.1.4\n';
    final marker = '\ndependencies:';
    final idx = content.indexOf(marker);
    if (idx == -1) {
      stdout.writeln(
        yellow(
          '  ⚠ could not find a `dependencies:` block; add `flutter_ota_kit` manually.',
        ),
      );
      return;
    }
    final insertAt = idx + marker.length;
    content = content.replaceRange(insertAt, insertAt, '\n$dep');
    pubspec.writeAsStringSync(content);
    step('Added `flutter_ota_kit` dependency to pubspec.yaml');
  }

  void _addInternetPermission() {
    final mf = File('android/app/src/main/AndroidManifest.xml');
    if (!mf.existsSync()) {
      stdout.writeln(
        yellow(
          '  ⚠ AndroidManifest.xml not found; skipping INTERNET permission.',
        ),
      );
      return;
    }
    var content = mf.readAsStringSync();
    if (content.contains('android.permission.INTERNET')) {
      step('INTERNET permission already present');
      return;
    }
    final match = RegExp(r'<manifest[^>]*>').firstMatch(content);
    if (match == null) {
      stdout.writeln(
        yellow(
          '  ⚠ could not locate <manifest> tag; add INTERNET permission manually.',
        ),
      );
      return;
    }
    final insertAt = match.end;
    content = content.replaceRange(
      insertAt,
      insertAt,
      '\n    <uses-permission android:name="android.permission.INTERNET" />',
    );
    mf.writeAsStringSync(content);
    step(
      'Added INTERNET permission to android/app/src/main/AndroidManifest.xml',
    );
  }

  Future<void> _writeSetupFile(
    FlutterPatcherConfig cfg,
    String provider,
  ) async {
    final dir = Directory('lib');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('lib/flutter_ota_kit_setup.dart');
    file.writeAsStringSync(_setupBody(cfg, provider));
    step('Wrote lib/flutter_ota_kit_setup.dart');
  }

  void _ensureGitignore() {
    final gi = File('.gitignore');
    final content = gi.existsSync() ? gi.readAsStringSync() : '';
    if (content.contains('.flutter_ota_kit/')) {
      step('.gitignore already ignores .flutter_ota_kit/');
      return;
    }
    final next = content.isEmpty
        ? '.flutter_ota_kit/\n'
        : '$content\n.flutter_ota_kit/\n';
    gi.writeAsStringSync(next);
    step('Added .flutter_ota_kit/ to .gitignore');
  }

  /// Write a `.env` scaffold for the selected backend. Every key is present but
  /// empty by default; any value supplied during `init` (interactive prompt or
  /// environment hint) is filled in so the app can be built with
  /// `flutter run --dart-define-from-file=.env`. Secrets always land here (env),
  /// never in committed source — the same values are also persisted to
  /// `.flutter_ota_kit/config.json` for the CLI.
  void _writeEnvFile(FlutterPatcherConfig cfg, String provider) {
    final entries = <String, String>{};
    switch (provider) {
      case 'postgres':
        final c = cfg.postgres;
        entries['POSTGRES_HOST'] = c.host ?? '';
        entries['POSTGRES_PORT'] = c.port ?? '5432';
        entries['POSTGRES_DB'] = c.database ?? 'postgres';
        entries['POSTGRES_USER'] = c.username ?? '';
        entries['POSTGRES_PASSWORD'] = c.password ?? '';
        entries['POSTGRES_SERVING_BASE_URL'] = c.servingBaseUrl ?? '';
        entries['CHANNEL'] = cfg.channel;
        entries['APP_VERSION'] = '';
      case 'cloudflare':
        final c = cfg.cloudflare;
        entries['CLOUDFLARE_ACCOUNT_ID'] = c.accountId ?? '';
        entries['CLOUDFLARE_D1_DATABASE_ID'] = c.d1DatabaseId ?? '';
        entries['CLOUDFLARE_API_TOKEN'] = c.apiToken ?? '';
        entries['R2_BUCKET'] = c.r2Bucket ?? 'bundles';
        entries['R2_ACCESS_KEY_ID'] = c.r2AccessKeyId ?? '';
        entries['R2_SECRET_ACCESS_KEY'] = c.r2SecretAccessKey ?? '';
        entries['R2_BASE_PATH'] = c.r2BasePath ?? '';
        entries['CHANNEL'] = cfg.channel;
        entries['APP_VERSION'] = '';
      case 'aws':
        final c = cfg.aws;
        entries['AWS_BUCKET'] = c.bucket ?? '';
        entries['AWS_REGION'] = c.region ?? '';
        entries['AWS_ACCESS_KEY_ID'] = c.accessKeyId ?? '';
        entries['AWS_SECRET_ACCESS_KEY'] = c.secretAccessKey ?? '';
        entries['AWS_ENDPOINT'] = c.endpoint ?? '';
        entries['AWS_BASE_PATH'] = c.basePath ?? '';
        entries['AWS_SESSION_TOKEN'] = c.sessionToken ?? '';
        entries['CHANNEL'] = cfg.channel;
        entries['APP_VERSION'] = '';
      case 'pocketbase':
        final c = cfg.pocketbase;
        entries['POCKETBASE_URL'] = c.url ?? '';
        entries['POCKETBASE_ADMIN_EMAIL'] = c.adminEmail ?? '';
        entries['POCKETBASE_ADMIN_PASSWORD'] = c.adminPassword ?? '';
        entries['POCKETBASE_BUNDLES_COLLECTION'] = c.bundlesCollection;
        entries['POCKETBASE_BUCKET'] = c.bundlesBucket;
        entries['CHANNEL'] = cfg.channel;
        entries['APP_VERSION'] = '';
      case 'supabase':
      default:
        final c = cfg.supabase;
        entries['SUPABASE_URL'] = c.url ?? '';
        entries['SUPABASE_PUBLISHABLE_KEY'] = c.anonKey ?? '';
        entries['SUPABASE_BUCKET'] = c.bucket ?? 'bundles';
        entries['CHANNEL'] = cfg.channel;
        entries['APP_VERSION'] = '';
        entries['SDK_VERSION'] = '1.0.0';
    }

    final buffer = StringBuffer();
    buffer.writeln('# Generated by `flutter-ota init $provider`.');
    buffer.writeln('# Fill in (or override) values, then build with:');
    buffer.writeln('#   flutter run --dart-define-from-file=.env');
    buffer.writeln(
      '# Environment overrides the project config and any defaults.',
    );
    for (final e in entries.entries) {
      buffer.writeln('${e.key}=${e.value}');
    }

    final file = File('.env');
    if (file.existsSync() && !(argResults!['force'] as bool)) {
      step('.env already exists; left untouched (use --force to overwrite)');
      return;
    }
    file.writeAsStringSync(buffer.toString());
    step('Wrote .env with $provider env scaffolding');
    _ensureEnvGitignored();
  }

  void _ensureEnvGitignored() {
    final gi = File('.gitignore');
    final lines = gi.existsSync()
        ? gi.readAsStringSync().split('\n')
        : const <String>[];
    if (lines.contains('.env')) {
      step('.gitignore already ignores .env');
      return;
    }
    final next = '${gi.existsSync() ? gi.readAsStringSync() : ''}\n.env\n';
    gi.writeAsStringSync(next);
    step('Added .env to .gitignore');
  }

  String _q(String? s) => s == null ? "''" : "'${s.replaceAll("'", "\\'")}'";

  /// Build the body of `lib/flutter_ota_kit_setup.dart` for the selected backend.
  ///
  /// Non-secret values default to the project config (written during `init` under
  /// `.flutter_ota_kit/`); every value can be overridden by a build-time
  /// `--dart-define` / `.env` (environment wins). Secrets (keys/tokens) default
  /// to empty and are ONLY read from the environment, never hard-coded here.
  String _setupBody(FlutterPatcherConfig cfg, String provider) {
    final channel = _q(cfg.channel);
    final appVersionExpr =
        "const String.fromEnvironment('APP_VERSION', defaultValue: '')";

    late final String configure;
    switch (provider) {
      case 'postgres':
        final c = cfg.postgres;
        configure =
            '''
  FlutterPatcher.configurePostgres(PostgresUpdateConfig(
    host: const String.fromEnvironment('POSTGRES_HOST', defaultValue: ${_q(c.host ?? '')}),
    port: int.tryParse(const String.fromEnvironment('POSTGRES_PORT', defaultValue: ${_q(c.port ?? '5432')})) ?? 5432,
    database: const String.fromEnvironment('POSTGRES_DB', defaultValue: ${_q(c.database ?? 'postgres')}),
    username: const String.fromEnvironment('POSTGRES_USER', defaultValue: ${_q(c.username ?? '')}),
    password: const String.fromEnvironment('POSTGRES_PASSWORD', defaultValue: ''),
    servingBaseUrl: const String.fromEnvironment('POSTGRES_SERVING_BASE_URL', defaultValue: ${_q(c.servingBaseUrl ?? '')}),
    channel: const String.fromEnvironment('CHANNEL', defaultValue: $channel),
    platform: Platform.android,
    updateStrategy: UpdateStrategy.appVersion,
    appVersion: $appVersionExpr,
  ));''';
      case 'cloudflare':
        final c = cfg.cloudflare;
        configure =
            '''
  FlutterPatcher.configureCloudflare(CloudflareUpdateConfig(
    accountId: const String.fromEnvironment('CLOUDFLARE_ACCOUNT_ID', defaultValue: ${_q(c.accountId ?? '')}),
    databaseId: const String.fromEnvironment('CLOUDFLARE_D1_DATABASE_ID', defaultValue: ${_q(c.d1DatabaseId ?? '')}),
    cloudflareApiToken: const String.fromEnvironment('CLOUDFLARE_API_TOKEN', defaultValue: ''),
    bucketName: const String.fromEnvironment('R2_BUCKET', defaultValue: ${_q(c.r2Bucket ?? 'bundles')}),
    accessKeyId: const String.fromEnvironment('R2_ACCESS_KEY_ID', defaultValue: ''),
    secretAccessKey: const String.fromEnvironment('R2_SECRET_ACCESS_KEY', defaultValue: ''),
    basePath: const String.fromEnvironment('R2_BASE_PATH', defaultValue: ${_q(c.r2BasePath ?? '')}),
    channel: const String.fromEnvironment('CHANNEL', defaultValue: $channel),
    platform: Platform.android,
    updateStrategy: UpdateStrategy.appVersion,
    appVersion: $appVersionExpr,
  ));''';
      case 'aws':
        final c = cfg.aws;
        configure =
            '''
  FlutterPatcher.configureAws(AwsUpdateConfig(
    bucketName: const String.fromEnvironment('AWS_BUCKET', defaultValue: ${_q(c.bucket ?? '')}),
    region: const String.fromEnvironment('AWS_REGION', defaultValue: ${_q(c.region ?? '')}),
    accessKeyId: const String.fromEnvironment('AWS_ACCESS_KEY_ID', defaultValue: ''),
    secretAccessKey: const String.fromEnvironment('AWS_SECRET_ACCESS_KEY', defaultValue: ''),
    basePath: const String.fromEnvironment('AWS_BASE_PATH', defaultValue: ${_q(c.basePath ?? '')}),
    endpoint: const String.fromEnvironment('AWS_ENDPOINT', defaultValue: ${_q(c.endpoint ?? '')}),
    channel: const String.fromEnvironment('CHANNEL', defaultValue: $channel),
    platform: Platform.android,
    updateStrategy: UpdateStrategy.appVersion,
    appVersion: $appVersionExpr,
  ));''';
      case 'pocketbase':
        final c = cfg.pocketbase;
        configure =
            '''
  FlutterPatcher.configurePocketBase(PocketBaseUpdateConfig(
    url: const String.fromEnvironment('POCKETBASE_URL', defaultValue: ${_q(c.url ?? '')}),
    adminEmail: const String.fromEnvironment('POCKETBASE_ADMIN_EMAIL', defaultValue: ''),
    adminPassword: const String.fromEnvironment('POCKETBASE_ADMIN_PASSWORD', defaultValue: ''),
    bundlesCollection: const String.fromEnvironment('POCKETBASE_BUNDLES_COLLECTION', defaultValue: ${_q(c.bundlesCollection)}),
    bundlesBucket: const String.fromEnvironment('POCKETBASE_BUCKET', defaultValue: ${_q(c.bundlesBucket)}),
    channel: const String.fromEnvironment('CHANNEL', defaultValue: $channel),
    platform: Platform.android,
    updateStrategy: UpdateStrategy.appVersion,
    appVersion: $appVersionExpr,
  ));''';
      case 'supabase':
      default:
        final c = cfg.supabase;
        configure =
            '''
  FlutterPatcher.configureSupabase(SupabaseUpdateConfig(
     supabaseUrl: const String.fromEnvironment('SUPABASE_URL', defaultValue: ${_q(c.url ?? '')}),
     anonKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY', defaultValue: ''),
     bucket: const String.fromEnvironment('SUPABASE_BUCKET', defaultValue: ${_q(c.bucket ?? 'bundles')}),
    channel: const String.fromEnvironment('CHANNEL', defaultValue: $channel),
    platform: Platform.android,
    updateStrategy: UpdateStrategy.appVersion,
    appVersion: $appVersionExpr,
    sdkVersion: const String.fromEnvironment('SDK_VERSION', defaultValue: '1.0.0'),
  ));''';
    }

    return '''
import 'package:flutter_ota_kit/flutter_ota_kit.dart';

// Generated by `flutter-ota init $provider`.
//
// Non-secret values default to the project config (`.flutter_ota_kit/config.json`
// set up during init); every value can be overridden by a build-time
// `--dart-define` / `.env` (environment wins). Secrets (keys/tokens) are never
// hard-coded here — supply them via `.env`.
//
// Call [setupFlutterOta] once in `main()`, after
// WidgetsFlutterBinding.ensureInitialized() and before runApp(). It wires the
// $provider update source and enables zero-click forced updates (the process
// restarts automatically when a forced bundle is available).
Future<void> setupFlutterOta() async {
$configure
  await FlutterPatcher.init(autoApplyUpdates: true);
}
''';
  }
}
