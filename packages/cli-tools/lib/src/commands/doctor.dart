import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';

import '../ui/ui.dart';

/// `flutter-ota doctor` — environment + backend connectivity check.
class DoctorCommand extends FlutterPatcherCommand {
  DoctorCommand({this.config, this.backendOverride}) {
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption(
      'backend',
      abbr: 'b',
      help: detected != null
          ? 'Backend provider [detected: $detected].'
          : 'Backend provider.',
    );
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Diagnose the local environment and backend connection.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('doctor');
    final steps = Steps('doctor');

    steps.success('Dart ${Platform.version.split(' ').first}');
    steps.success(
      'OS ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion.split('\n').first}',
    );

    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    if (cfg == null) {
      steps.fail('Config not found — run ${bold('flutter-ota init')}');
      steps.summary();
      return;
    }
    steps.success('Provider ${cfg.provider}');
    steps.success('Channel ${cfg.channel}');
    steps.success('Platform ${cfg.platform}');

    // Backend-specific pre-flight checks.
    await _checkProvider(cfg, steps);

    try {
      final backend = requireBackend(cfg, override: backendOverride);
      final sw = Stopwatch()..start();
      final channels = await backend.db.getChannels();
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      final time = ms >= 1000
          ? '${(ms / 1000).toStringAsFixed(1)}s'
          : '${ms}ms';
      steps.success('Backend reachable — ${channels.join(', ')} in $time');
    } catch (e) {
      steps.fail('Backend unreachable — $e');
    }
    steps.summary();
  });

  Future<void> _checkProvider(FlutterPatcherConfig cfg, Steps steps) async {
    switch (cfg.provider) {
      case 'supabase':
        await _checkSupabase(cfg, steps);
      case 'postgres':
        await _checkPostgres(cfg, steps);
      case 'cloudflare':
        await _checkCloudflare(cfg, steps);
      case 'aws':
        await _checkAws(cfg, steps);
      case 'pocketbase':
        await _checkPocketBase(cfg, steps);
      default:
        steps.fail('Unknown provider: ${cfg.provider}');
    }
  }

  Future<void> _checkSupabase(FlutterPatcherConfig cfg, Steps steps) async {
    final url = cfg.supabase.url;
    if (url == null || url.isEmpty) {
      steps.fail('SUPABASE_URL not set');
      return;
    }
    try {
      final res = await http
          .get(Uri.parse('$url/rest/v1/'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode < 400) {
        steps.success('Supabase reachable ($url)');
      } else {
        steps.fail('Supabase returned ${res.statusCode}');
      }
    } catch (e) {
      steps.fail('Supabase unreachable — $e');
    }
  }

  Future<void> _checkPostgres(FlutterPatcherConfig cfg, Steps steps) async {
    final host = cfg.postgres.host;
    if (host == null || host.isEmpty) {
      steps.fail('POSTGRES_HOST not set');
      return;
    }
    final port = int.tryParse(cfg.postgres.port ?? '5432') ?? 5432;
    try {
      final socket = await Socket.connect(
        host,
        port,
      ).timeout(const Duration(seconds: 5));
      await socket.close();
      steps.success('Postgres reachable ($host:$port)');
    } catch (e) {
      steps.fail('Postgres unreachable — $e');
    }
  }

  Future<void> _checkCloudflare(FlutterPatcherConfig cfg, Steps steps) async {
    final accountId = cfg.cloudflare.accountId;
    final apiToken = cfg.cloudflare.apiToken;
    if (accountId == null || accountId.isEmpty) {
      steps.fail('CLOUDFLARE_ACCOUNT_ID not set');
      return;
    }
    if (apiToken == null || apiToken.isEmpty) {
      steps.fail('CLOUDFLARE_API_TOKEN not set');
      return;
    }
    try {
      final res = await http
          .get(
            Uri.parse(
              'https://api.cloudflare.com/client/v4/accounts/$accountId',
            ),
            headers: {
              'Authorization': 'Bearer $apiToken',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] == true) {
        steps.success('Cloudflare account reachable');
      } else {
        final errors = body['errors'] as List? ?? [];
        final msg = errors.isNotEmpty ? errors.first['message'] : res.body;
        steps.fail('Cloudflare API error: $msg');
      }
    } catch (e) {
      steps.fail('Cloudflare unreachable — $e');
    }
  }

  Future<void> _checkAws(FlutterPatcherConfig cfg, Steps steps) async {
    final bucket = cfg.aws.bucket;
    if (bucket == null || bucket.isEmpty) {
      steps.fail('AWS_BUCKET not set');
      return;
    }
    final region = cfg.aws.region;
    if (region == null || region.isEmpty) {
      steps.fail('AWS_REGION not set');
      return;
    }
    steps.success('AWS S3 bucket "$bucket" in $region');
  }

  Future<void> _checkPocketBase(FlutterPatcherConfig cfg, Steps steps) async {
    final paths = PocketBaseInstallPaths.resolve();
    final installed = await paths.binaryPath.exists();
    if (installed) {
      steps.success('PocketBase binary at ${paths.binaryPath.path}');
    } else {
      steps.fail(
        'PocketBase not installed — run ${bold('flutter-ota pocketbase install')}',
      );
    }
    final url = cfg.pocketbase.url;
    if (url != null && url.isNotEmpty) {
      final client = PocketBaseClient(url);
      try {
        final ok = await client.health();
        if (ok) {
          steps.success('PocketBase reachable');
        } else {
          steps.fail('PocketBase unreachable');
        }
      } catch (e) {
        steps.fail('PocketBase unreachable — $e');
      } finally {
        client.close();
      }
    }
  }
}
