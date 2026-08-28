import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_patcher_cli/flutter_patcher_cli.dart';

import '../ui/ui.dart';

/// `flutter_patcher doctor` — environment + backend connectivity check.
class DoctorCommand extends FlutterPatcherCommand {
  DoctorCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Diagnose the local environment and backend connection.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Backend provider.');

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
          lines.add(kv('config', yellow('not found — run `flutter_patcher init`')));
          box('doctor', lines);
          return;
        }
        lines
          ..add(kv('provider', cfg.provider))
          ..add(kv('channel', cfg.channel))
          ..add(kv('platform', cfg.platform));
        try {
          final backend = requireBackend(cfg, override: backendOverride);
          final channels = await backend.db.getChannels();
          lines.add(kv('backend', green('reachable — ${channels.join(', ')}')));
        } catch (e) {
          lines.add(kv('backend', red('unreachable — $e')));
        }
        box('doctor', lines);
      });
}
