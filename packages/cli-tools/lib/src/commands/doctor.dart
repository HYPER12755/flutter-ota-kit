import 'dart:io';

import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';

import '../ui/ui.dart';

/// `flutter-ota doctor` — environment + backend connectivity check.
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

    // PocketBase-specific: show binary + health endpoint status.
    if (cfg.provider == 'pocketbase') {
      await _checkPocketBase(cfg, steps);
    }

    try {
      final backend = requireBackend(cfg, override: backendOverride);
      final sw = Stopwatch()..start();
      final channels = await backend.db.getChannels();
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      final time = ms >= 1000
          ? '${(ms / 1000).toStringAsFixed(1)}s'
          : '${ms}ms';
      steps.success(
        'Backend reachable — ${channels.join(', ')} in $time',
      );
    } catch (e) {
      steps.fail('Backend unreachable — $e');
    }
    steps.summary();
  });

  Future<void> _checkPocketBase(
    FlutterPatcherConfig cfg,
    Steps steps,
  ) async {
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
      try {
        final client = PocketBaseClient(url);
        final ok = await client.health();
        if (ok) {
          steps.success('PocketBase reachable');
        } else {
          steps.fail('PocketBase unreachable');
        }
      } catch (e) {
        steps.fail('PocketBase unreachable — $e');
      }
    }
  }
}
