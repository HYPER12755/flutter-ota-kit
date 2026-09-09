import 'dart:io';

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
  String get description => 'Open the flutter-ota web console.';

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
      throw PackException(
        'Console package not found (expected packages/console).',
        1,
      );
    }
    if (argResults!['open'] as bool) {
      banner('console · open');
      step('Launching console...');
      final process = await Process.start(
        'flutter',
        ['run', '-d', 'chrome'],
        workingDirectory: consoleDir.path,
        runInShell: true,
        mode: ProcessStartMode.inheritStdio,
      );
      final code = await process.exitCode;
      if (code != 0) err('flutter run exited with code $code');
      return;
    }
    banner('console');
    info('Open the web console with Flutter:');
    step('dir  ${dim(consoleDir.path)}');
    step('run  ${cyan('flutter run -d chrome')}');
  });
}
