import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../backend.dart';
import '../cli_base.dart';
import '../config.dart';
import '../operations.dart';

/// `flutter_patcher rollback` — disable the latest enabled bundle on a channel.
class RollbackCommand extends Command<int> {
  RollbackCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'rollback';

  @override
  String get description =>
      'Disable the latest enabled bundle on a channel (roll back).';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Backend provider.')
    ..addOption('channel', abbr: 'c', help: 'Channel to roll back.');

  @override
  Future<int> run() => runGuarded(() async {
        final channel = argResults!['channel'] as String?;
        if (channel == null || channel.isEmpty) {
          throw StateError('Usage: flutter_patcher rollback --channel <channel>');
        }
        final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
        final backend = requireBackend(cfg, override: backendOverride);
        final id = await rollbackChannel(backend, channel);
        stdout.writeln('Rolled back channel "$channel" (disabled bundle $id)');
      });
}
