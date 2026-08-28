import 'dart:io';

import 'package:args/command_runner.dart';
import 'ui/ui.dart';

/// Custom [CommandRunner] that renders a clean, colorized top-level help.
class FlutterPatcherRunner extends CommandRunner<int> {
  FlutterPatcherRunner(super.name, super.description);

  @override
  String get usage {
    final names = commands.keys.toList()..sort();
    var maxName = 0;
    for (final n in names) {
      maxName = maxName < n.length ? n.length : maxName;
    }
    final buf = StringBuffer();
    buf.writeln('  ${cyan('▶')} ${cyan(bold(executableName))} '
        '${dim('·')} ${bold(description)}');
    buf.writeln('  ${dim('─' * 60)}');
    buf.writeln('');
    buf.writeln('  ${bold('USAGE')}');
    buf.writeln('    $executableName <command> [arguments]');
    buf.writeln('');
    buf.writeln('  ${bold('COMMANDS')}');
    for (final n in names) {
      final c = commands[n]!;
      buf.writeln('    ${cyan(n.padRight(maxName))}  ${dim(c.description)}');
    }
    buf.writeln('');
    buf.writeln('  ${dim('Run "$executableName help <command>" for more about a command.')}');
    return buf.toString();
  }

  @override
  void printUsage([String? usage]) {
    stdout.writeln(usage ?? this.usage);
  }
}

String _fullName(Command<int> command) {
  final parts = <String>[command.name];
  var p = command.parent;
  while (p != null) {
    parts.insert(0, p.name);
    p = p.parent;
  }
  return parts.join(' ');
}

/// Base class for flutter_patcher commands; renders a clean, colorized
/// per-command help (used by `flutter_patcher <cmd> --help`).
abstract class FlutterPatcherCommand extends Command<int> {
  @override
  String get usage {
    final buf = StringBuffer();
    buf.writeln('  ${cyan(bold(name))} ${dim('·')} $description');
    buf.writeln('');
    buf.writeln('  ${bold('USAGE')}');
    buf.writeln('    ${_fullName(this)} [arguments]');
    if (argParser.options.isNotEmpty) {
      buf.writeln('');
      buf.writeln('  ${bold('OPTIONS')}');
      buf.writeln('  ${argParser.usage.replaceAll('\n', '\n  ')}');
    }
    return buf.toString();
  }

  @override
  void printUsage([String? usage]) {
    stdout.writeln(usage ?? this.usage);
  }
}
