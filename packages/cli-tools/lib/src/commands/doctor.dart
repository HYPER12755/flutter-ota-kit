import 'dart:io';

import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';

import '../ui/ui.dart';

/// `flutter_ota_kit doctor` — environment + backend connectivity check.
class DoctorCommand extends FlutterPatcherCommand {
  DoctorCommand({this.config, this.backendOverride}) {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
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
    final lines = <String>[
      kv('dart', Platform.version.split(' ').first),
      kv(
        'os',
        '${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion.split('\n').first}',
      ),
    ];
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    if (cfg == null) {
      lines.add(kv('config', yellow('not found — run `flutter-ota init`')));
      box('doctor', lines);
      return;
    }
    lines
      ..add(kv('provider', cfg.provider))
      ..add(kv('channel', cfg.channel))
      ..add(kv('platform', cfg.platform));

    // PocketBase-specific: show binary + health endpoint status.
    if (cfg.provider == 'pocketbase') {
      await _checkPocketBase(cfg, lines);
    }

    try {
      final backend = requireBackend(cfg, override: backendOverride);
      final channels = await backend.db.getChannels();
      lines.add(kv('backend', green('reachable — ${channels.join(', ')}')));
    } catch (e) {
      lines.add(kv('backend', red('unreachable — $e')));
    }
    box('doctor', lines);
  });

  Future<void> _checkPocketBase(
    FlutterPatcherConfig cfg,
    List<String> lines,
  ) async {
    final paths = PocketBaseInstallPaths.resolve();
    final installed = await paths.binaryPath.exists();
    lines.add(
      kv(
        'pocketbase binary',
        installed
            ? green('installed at ${paths.binaryPath.path}')
            : yellow(
                'not installed — run `flutter-ota pocketbase install`',
              ),
      ),
    );
    // Probe the health endpoint if a URL is configured.
    final url = cfg.pocketbase.url;
    if (url != null && url.isNotEmpty) {
      try {
        final client = PocketBaseClient(url);
        final ok = await client.health();
        lines.add(
          kv('pocketbase health', ok ? green('reachable') : red('unreachable')),
        );
      } catch (e) {
        lines.add(kv('pocketbase health', red('unreachable — $e')));
      }
    }
  }
}
