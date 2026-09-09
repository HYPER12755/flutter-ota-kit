import 'dart:convert';
import 'dart:io';

import '../cli_base.dart';
import '../config.dart';
import '../ui/ui.dart' as ui;

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
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  if (!Platform.isWindows) {
    Process.runSync('chmod', ['600', file.path]);
  }
}

class ConfigGetCommand extends FlutterPatcherCommand {
  ConfigGetCommand() {
    argParser.addOption('key', abbr: 'k', help: 'Dot-path key.');
  }

  @override
  String get name => 'get';

  @override
  String get description =>
      'Print a config value by dot-path (e.g. supabase.url).';

  @override
  Future<int> run() => runGuarded(() async {
    ui.banner('config · get');
    final key = argResults!['key'] as String? ??
        (argResults!.rest.isNotEmpty ? argResults!.rest.first : null);
    if (key == null || key.isEmpty) {
      throw StateError('Usage: flutter-ota config get <key>');
    }
    final value = readPath(_loadProjectJson(), key);
    if (value == null) {
      ui.warn('(not set)');
      return;
    }
    stdout.writeln(
      value is String ? value : const JsonEncoder().convert(value),
    );
  });
}

class ConfigSetCommand extends FlutterPatcherCommand {
  ConfigSetCommand() {
    argParser.addOption('key', abbr: 'k', help: 'Dot-path key.');
    argParser.addOption('value', help: 'Value.');
  }

  @override
  String get name => 'set';

  @override
  String get description => 'Set a config value by dot-path.';

  @override
  Future<int> run() => runGuarded(() async {
    final key = argResults!['key'] as String? ??
        (argResults!.rest.isNotEmpty ? argResults!.rest.first : null);
    final value = argResults!['value'] as String? ??
        (argResults!.rest.length > 1 ? argResults!.rest[1] : null);
    if (key == null || key.isEmpty || value == null) {
      throw StateError('Usage: flutter-ota config set <key> <value>');
    }
    final json = _loadProjectJson();
    writePath(json, key, value);
    _saveProjectJson(json);
    ui.banner('config · set');
    ui.step('$key = $value');
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
    if (json.isEmpty) {
      ui.banner('config');
      ui.warn('No config found. Run flutter-ota init to create one.');
      return;
    }
    ui.banner('config');
    _printConfig(json, '');
  });
}

void _printConfig(Map<String, dynamic> json, String prefix) {
  for (final entry in json.entries) {
    final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
    final value = entry.value;
    if (value is Map<String, dynamic>) {
      _printConfig(value, key);
    } else {
      final display = value is String ? value : const JsonEncoder().convert(value);
      stdout.writeln(ui.kv(key, display));
    }
  }
}
