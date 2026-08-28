import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../cli_base.dart';

/// `flutter_patcher console` — open the web console.
class ConsoleCommand extends Command<int> {
  @override
  String get name => 'console';

  @override
  String get description => 'Open the flutter_patcher web console.';

  @override
  ArgParser get argParser => ArgParser()
    ..addFlag('open',
        help: 'Launch the console with `flutter run -d chrome` (requires Flutter).');

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
          stdout.writeln('Console package not found (expected packages/console).');
          return;
        }
        if (argResults!['open'] as bool) {
          stdout.writeln('Launching console...');
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
        stdout.writeln('flutter_patcher web console:');
        stdout.writeln('  cd ${consoleDir.path}');
        stdout.writeln('  flutter run -d chrome');
      });
}
