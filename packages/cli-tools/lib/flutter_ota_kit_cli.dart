/// flutter_ota_kit_cli — command-line interface for flutter_ota_kit.
///
/// Faithful Dart port of hot-updater's `@hot-updater/cli`: deploy bundles,
/// manage channels/rollbacks, run migrations, and inspect the backend.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

export 'src/backend.dart';
export 'src/cli_base.dart';
export 'src/config.dart';
export 'src/operations.dart';
export 'src/pack.dart';
export 'src/sign.dart';
export 'src/util.dart';

export 'src/commands/init.dart';
export 'src/commands/config_command.dart';
export 'src/commands/keys.dart';
export 'src/commands/doctor.dart';
export 'src/commands/fingerprint.dart';
export 'src/commands/deploy.dart';
export 'src/commands/bundle.dart';
export 'src/commands/build.dart';
export 'src/commands/rollback.dart';
export 'src/commands/channel.dart';
export 'src/commands/migrate.dart';
export 'src/commands/console.dart';

import 'src/commands/build.dart';
import 'src/commands/bundle.dart';
import 'src/runner.dart';
import 'src/commands/channel.dart';
import 'src/commands/config_command.dart';
import 'src/commands/console.dart';
import 'src/commands/deploy.dart';
import 'src/commands/doctor.dart';
import 'src/commands/fingerprint.dart';
import 'src/commands/init.dart';
import 'src/commands/keys.dart';
import 'src/commands/migrate.dart';
import 'src/commands/rollback.dart';
import 'src/commands/storage.dart';

/// Entry point: build the command runner and dispatch [args].
Future<int> run(List<String> args) async {
  final runner = FlutterPatcherRunner(
    'flutter_ota_kit',
    'flutter_ota_kit CLI — OTA code push for Flutter (hot-updater compatible).',
  )
    ..addCommand(InitCommand())
    ..addCommand(ConfigCommand())
    ..addCommand(KeysCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(FingerprintCommand())
    ..addCommand(DeployCommand())
    ..addCommand(BuildCommand())
    ..addCommand(BundleCommand())
    ..addCommand(RollbackCommand())
    ..addCommand(ChannelCommand())
    ..addCommand(StorageCommand())
    ..addCommand(MigrateCommand())
    ..addCommand(ConsoleCommand());

  try {
    final result = await runner.run(args);
    return result ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('');
    stderr.writeln(e.usage);
    return 64;
  }
}
