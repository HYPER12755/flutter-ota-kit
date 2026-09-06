import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';
import 'package:path/path.dart' as p;

import '../ui/ui.dart';

/// `flutter_ota_kit console` — open the web console.
class ConsoleCommand extends FlutterPatcherCommand {
  ConsoleCommand() {
    argParser.addFlag(
      'open',
      help:
          'Launch the console with `flutter run -d chrome` (requires Flutter).',
    );
  }

  @override
  String get name => 'console';

  @override
  String get description => 'Open the flutter_ota_kit web console.';

  Directory? _findConsoleDir() {
    var dir = Directory(p.dirname(Platform.script.path));
    while (dir.path != dir.parent.path) {
      final candidate = Directory(p.join(dir.path, 'packages', 'console'));
      if (candidate.existsSync()) return candidate;
      dir = dir.parent;
    }
    return null;
  }

  @override
  Future<int> run() => runGuarded(() async {
    final consoleDir = _findConsoleDir();
    if (consoleDir == null) {
      err('Console package not found (expected packages/console).');
      return;
    }
    if (argResults!['open'] as bool) {
      step('Launching console...');
      final process = await Process.start(
        'flutter',
        ['run', '-d', 'chrome'],
        workingDirectory: consoleDir.path,
        runInShell: true,
        mode: ProcessStartMode.inheritStdio,
      );
      exitCode = await process.exitCode;
      return;
    }
    banner('console');
    box('flutter_ota_kit console', [
      'Open the web console with Flutter:',
      '',
      kv('dir', consoleDir.path),
      kv('run', 'flutter run -d chrome'),
    ]);
  });
}
