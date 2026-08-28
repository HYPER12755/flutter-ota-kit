import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../backend.dart';
import '../cli_base.dart';
import '../config.dart';

/// `flutter_patcher doctor` — environment + backend connectivity check.
class DoctorCommand extends Command<int> {
  DoctorCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'doctor';

  @override
  String get description => 'Diagnose the local environment and backend connection.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Backend provider.');

  @override
  Future<int> run() => runGuarded(() async {
        stdout.writeln('flutter_patcher CLI doctor');
        stdout.writeln('  dart:   ${Platform.version.split(' ').first}');
        stdout.writeln('  os:     ${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion.split('\n').first}');
        final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
        if (cfg == null) {
          stdout.writeln('  config: not found (run `flutter_patcher init`)');
          return;
        }
        stdout.writeln('  config: provider=${cfg.provider} '
            'channel=${cfg.channel} platform=${cfg.platform}');
        try {
          final backend = requireBackend(cfg, override: backendOverride);
          final channels = await backend.db.getChannels();
          stdout.writeln('  backend: reachable (channels: ${channels.join(', ')})');
        } catch (e) {
          stdout.writeln('  backend: unreachable — $e');
        }
      });
}
