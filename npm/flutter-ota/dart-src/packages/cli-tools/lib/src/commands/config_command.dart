import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../cli_base.dart';
import '../config.dart';

/// `flutter_ota_kit config` — get/set/list config values.
class ConfigCommand extends FlutterPatcherCommand {
  ConfigCommand() {
    addSubcommand(ConfigGetCommand());
    addSubcommand(ConfigSetCommand());
    addSubcommand(ConfigListCommand());
  }

  @override
  String get name => 'config';

  @override
  String get description => 'Get, set, or list configuration values.';

  @override
  Future<int> run() => runGuarded(() async {
        // No subcommand selected.
        print(description);
        print(''); print('Subcommands:'); print('  get <key>'); print('  set <key> <value>'); print('  list');
      });
}

Map<String, dynamic> _loadProjectJson() {
  final file = configCandidates().first;
  if (!file.existsSync()) return <String, dynamic>{};
  final raw = file.readAsStringSync();
  if (raw.trim().isEmpty) return <String, dynamic>{};
  return jsonDecode(raw) as Map<String, dynamic>;
}

void _saveProjectJson(Map<String, dynamic> json) {
  final file = configCandidates().first;
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(json),
  );
}

class ConfigGetCommand extends FlutterPatcherCommand {
  @override
  String get name => 'get';

  @override
  String get description => 'Print a config value by dot-path (e.g. supabase.url).';

  @override
  ArgParser get argParser => ArgParser()..addOption('key', abbr: 'k', help: 'Dot-path key.');

  @override
  Future<int> run() => runGuarded(() async {
        final key = argResults!['key'] as String?;
        if (key == null || key.isEmpty) {
          throw StateError('Usage: flutter_ota_kit config get <key>');
        }
        final value = readPath(_loadProjectJson(), key);
        if (value == null) {
          stderr.writeln('(not set)');
          return;
        }
        stdout.writeln(
          value is String ? value : const JsonEncoder().convert(value),
        );
      });
}

class ConfigSetCommand extends FlutterPatcherCommand {
  @override
  String get name => 'set';

  @override
  String get description => 'Set a config value by dot-path.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('key', abbr: 'k', help: 'Dot-path key.')
    ..addOption('value', help: 'Value.');

  @override
  Future<int> run() => runGuarded(() async {
        final key = argResults!['key'] as String?;
        final value = argResults!['value'] as String?;
        if (key == null || key.isEmpty || value == null) {
          throw StateError('Usage: flutter_ota_kit config set <key> <value>');
        }
        final json = _loadProjectJson();
        writePath(json, key, value);
        _saveProjectJson(json);
        stdout.writeln('Set $key = $value');
      });
}

class ConfigListCommand extends FlutterPatcherCommand {
  @override
  String get name => 'list';

  @override
  String get description => 'Print the full config.';

  @override
  Future<int> run() => runGuarded(() async {
        final json = _loadProjectJson();
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(json));
      });
}
