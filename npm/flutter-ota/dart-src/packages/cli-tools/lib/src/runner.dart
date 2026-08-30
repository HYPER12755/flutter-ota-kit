import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'ui/ui.dart';
import 'verbose.dart';

/// Custom [CommandRunner] that renders a clean, colorized top-level help.
class FlutterPatcherRunner extends CommandRunner<int> {
  FlutterPatcherRunner(super.name, super.description) {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show full error stack traces.',
      negatable: false,
    );
  }

  @override
  Future<int?> runCommand(ArgResults results) {
    verboseMode = results['verbose'] as bool? ?? false;
    return super.runCommand(results);
  }

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
    buf.writeln('');
    buf.writeln('  ${bold('GLOBAL OPTIONS')}');
    buf.writeln('    ${cyan('-v, --verbose')}  ${dim('Show full error stack traces.')}');
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

/// Base class for flutter_ota_kit commands; renders a clean, colorized
/// per-command help (used by `flutter_ota_kit <cmd> --help`).
abstract class FlutterPatcherCommand extends Command<int> {
  @override
  String get usage {
    final buf = StringBuffer();
    buf.writeln('  ${cyan('▶')} ${cyan(bold(name))} ${dim('·')} ${bold(description)}');
    buf.writeln('  ${dim('─' * 60)}');
    buf.writeln('');
    buf.writeln('  ${bold('USAGE')}');
    buf.writeln('    ${_fullName(this)} [arguments]');
    if (subcommands.isNotEmpty) {
      final names = subcommands.keys.toList()..sort();
      var maxName = 0;
      for (final n in names) {
        if (n.length > maxName) maxName = n.length;
      }
      buf.writeln('');
      buf.writeln('  ${bold('COMMANDS')}');
      for (final n in names) {
        final c = subcommands[n]!;
        buf.writeln('    ${cyan(n.padRight(maxName))}  ${dim(c.description)}');
      }
      buf.writeln('');
      buf.writeln('  ${dim('Run "${_fullName(this)} <command>" for more about a command.')}');
    }
    if (argParser.options.isNotEmpty) {
      buf.writeln('');
      buf.writeln('  ${bold('OPTIONS')}');
      for (final opt in argParser.options.values) {
        final flags = <String>[];
        if (opt.abbr != null && opt.abbr!.isNotEmpty) flags.add('-${opt.abbr}');
        flags.add('--${opt.name}');
        final flagStr = flags.join(', ');
        buf.writeln('    ${cyan(flagStr.padRight(22))}  ${dim(opt.help ?? '')}');
      }
    }
    return buf.toString();
  }

  @override
  void printUsage([String? usage]) {
    stdout.writeln(usage ?? this.usage);
  }
}
