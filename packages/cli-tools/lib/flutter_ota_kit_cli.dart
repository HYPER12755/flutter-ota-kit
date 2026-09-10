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
export 'src/pocketbase/installer.dart';
export 'src/pocketbase/process_manager.dart';
export 'src/pocketbase/schema_installer.dart';
export 'src/pocketbase/data_bootstrap.dart';
export 'src/sign.dart';
export 'src/util.dart';

// Re-export the PocketBase client so CLI commands can probe PB health
// without pulling the plugin in separately.
export 'package:flutter_ota_kit_pocketbase/flutter_ota_kit_pocketbase.dart'
    show PocketBaseClient;

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
export 'src/commands/pocketbase.dart';
export 'src/commands/storage.dart';

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
import 'src/commands/pocketbase.dart';
import 'src/commands/rollback.dart';
import 'src/commands/storage.dart';

/// Entry point: build the command runner and dispatch [args].
Future<int> run(List<String> args) async {
  final runner =
      FlutterPatcherRunner(
          'flutter-ota',
          'flutter-ota CLI — OTA code push for Flutter (hot-updater compatible).',
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
        ..addCommand(ConsoleCommand())
        ..addCommand(PocketBaseCommand());

  try {
    final result = await runner.run(args);
    return result ?? 0;
  } on UsageException catch (e) {
    final msg = e.message;

    // Missing subcommand → show the command's own help + suggestions.
    if (msg.startsWith('Missing subcommand')) {
      final match = RegExp(r'"flutter-ota (\w+)"').firstMatch(msg);
      if (match != null) {
        final cmd = runner.commands[match.group(1)];
        if (cmd != null) {
          _printMissingSubcommand(cmd);
          return 0;
        }
      }
    }

    // No command given → show top-level help.
    if (msg.contains('No command specified')) {
      runner.printUsage();
      return 0;
    }

    // Unknown command → fuzzy-match and suggest.
    final unknownMatch = RegExp(r'Could not find a command named "?(\w+)"?')
        .firstMatch(msg);
    if (unknownMatch != null) {
      final typed = unknownMatch.group(1)!;
      _printUnknownCommand(runner, typed);
      return 64;
    }

    // Unknown subcommand → suggest closest subcommand.
    final subMatch = RegExp(
      r'Could not find a subcommand named "?(\w+)"? for "?flutter-ota (\w+)"?',
    ).firstMatch(msg);
    if (subMatch != null) {
      final subTyped = subMatch.group(1)!;
      final parentName = subMatch.group(2)!;
      final parentCmd = runner.commands[parentName];
      if (parentCmd != null) {
        _printUnknownSubcommand(parentCmd, subTyped);
        return 64;
      }
    }

    // Fallback — show the raw error + usage.
    stderr.writeln(e.message);
    stderr.writeln('');
    stderr.writeln(e.usage);
    return 64;
  }
}

/// Show a helpful "unknown command" message with fuzzy-match suggestions.
void _printUnknownCommand(FlutterPatcherRunner runner, String typed) {
  final commands = runner.commands.keys.toList();

  // Exact prefix match (e.g. "bund" → "bundle").
  final prefixMatches = commands.where((c) => c.startsWith(typed)).toList();

  // Levenshtein-based fuzzy match for short typos.
  final fuzzyMatches = <String>[];
  for (final c in commands) {
    if (prefixMatches.contains(c)) continue;
    if (_levenshtein(typed, c) <= 2) {
      fuzzyMatches.add(c);
    }
  }

  // Subcommand matching (e.g. "bundle lis" → suggest "list").
  final subMatch = RegExp(r'^(\w+)\s+(\w+)$').firstMatch(typed);
  String? parentCmd;
  String? subTyped;
  if (subMatch != null) {
    parentCmd = subMatch.group(1);
    subTyped = subMatch.group(2);
  }
  // Also try if typed is just the first part.
  if (parentCmd != null && !commands.contains(parentCmd)) {
    // Check if parentCmd is a fuzzy match for a real command.
    final parentFuzzy = commands.where((c) {
      if (c == parentCmd) return true;
      return _levenshtein(parentCmd!, c) <= 2;
    }).toList();
    if (parentFuzzy.isNotEmpty) {
      parentCmd = parentFuzzy.first;
    }
  }

  stderr.writeln('');
  stderr.writeln('  ${_red('✗')} Unknown command: ${_red(typed)}');
  stderr.writeln('');

  if (prefixMatches.isNotEmpty || fuzzyMatches.isNotEmpty) {
    final suggestions = [...prefixMatches, ...fuzzyMatches];
    stderr.writeln('  ${_cyan('Did you mean?')}');
    for (final s in suggestions.take(3)) {
      stderr.writeln('    ${_green(s)}');
    }
    stderr.writeln('');

    // If it looks like "parent sub" but the sub is wrong, show sub help.
    if (parentCmd != null && subTyped != null) {
      final cmd = runner.commands[parentCmd];
      final sub = subTyped;
      if (cmd != null && cmd.subcommands.isNotEmpty) {
        final subNames = cmd.subcommands.keys.toList();
        final subSuggestion = subNames
            .where((s) => s.startsWith(sub) || _levenshtein(sub, s) <= 2)
            .toList();
        if (subSuggestion.isNotEmpty) {
          stderr.writeln(
            '  ${_cyan('Did you mean?')} $parentCmd ${_green(subSuggestion.first)}',
          );
          stderr.writeln('');
        }
        cmd.printUsage();
        return;
      }
    }

    // Show top-level help.
    runner.printUsage();
    return;
  }

  // No close matches — show all available commands.
  runner.printUsage();
}

/// Show a helpful "unknown subcommand" message with suggestions.
void _printUnknownSubcommand(Command<int> parent, String typed) {
  final subNames = parent.subcommands.keys.toList();

  // Find closest subcommands.
  final suggestions = subNames
      .where((s) => s.startsWith(typed) || _levenshtein(typed, s) <= 2)
      .toList();

  stderr.writeln('');
  stderr.writeln(
    '  ${_red('✗')} Unknown subcommand: ${_red(typed)} for ${_cyan('flutter-ota ${parent.name}')}',
  );
  stderr.writeln('');

  if (suggestions.isNotEmpty) {
    stderr.writeln('  ${_cyan('Did you mean?')}');
    for (final s in suggestions.take(3)) {
      stderr.writeln('    ${_green(s)}');
    }
    stderr.writeln('');
  }

  parent.printUsage();
}

/// Show a helpful "missing subcommand" message with all subcommand suggestions.
void _printMissingSubcommand(Command<int> parent) {
  final subNames = parent.subcommands.keys.toList()..sort();

  stderr.writeln('');
  stderr.writeln(
    '  ${_red('✗')} Missing subcommand for ${_cyan('flutter-ota ${parent.name}')}',
  );
  stderr.writeln('');

  if (subNames.isNotEmpty) {
    stderr.writeln('  ${_cyan('Available subcommands:')}');
    for (final s in subNames) {
      stderr.writeln('    ${_green('${parent.name} $s')}');
    }
    stderr.writeln('');
  }

  parent.printUsage();
}

// ── Minimal Levenshtein distance ──────────────────────────────────────────────

int _levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final dp = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) dp[i][0] = i;
  for (var j = 0; j <= b.length; j++) dp[0][j] = j;
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      dp[i][j] = [
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      ].reduce((a, b) => a < b ? a : b);
    }
  }
  return dp[a.length][b.length];
}

// ── Minimal inline color helpers (stderr-safe, TTY-aware) ────────────────────

bool get _noColor {
  final v = Platform.environment['NO_COLOR'];
  return v != null && v.isNotEmpty;
}

bool get _colorOn =>
    !_noColor && stderr.hasTerminal && stderr.supportsAnsiEscapes;

String _red(String s) => _colorOn ? '\x1b[31m$s\x1b[0m' : s;
String _green(String s) => _colorOn ? '\x1b[32m$s\x1b[0m' : s;
String _cyan(String s) => _colorOn ? '\x1b[36m$s\x1b[0m' : s;
