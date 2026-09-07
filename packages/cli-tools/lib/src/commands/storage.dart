import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';

import '../ui/ui.dart';

/// `flutter_ota_kit storage` — inspect and clean the blob storage bucket
/// directly from the CLI (no need to open the provider dashboard).
class StorageCommand extends FlutterPatcherCommand {
  StorageCommand({this.config, this.backendOverride}) {
    addSubcommand(
      StorageListCommand(config: config, backendOverride: backendOverride),
    );
    addSubcommand(
      StorageDeleteCommand(config: config, backendOverride: backendOverride),
    );
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'storage';

  @override
  String get description =>
      'Inspect and manage bundle storage objects (find / delete orphans).';
}

class StorageListCommand extends FlutterPatcherCommand {
  StorageListCommand({this.config, this.backendOverride}) {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
    argParser.addOption('prefix', help: 'Key prefix filter (e.g. bundles).');
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'list';

  @override
  String get description => 'List storage objects.';

  @override
  Future<int> run() => runGuarded(() async {
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    final prefix = argResults!['prefix'] as String?;
    banner('storage · list');
    final steps = Steps('list');
    final objects = await steps.run('Listing storage objects', () =>
        backend.storage.listObjects(
            prefix == null || prefix.isEmpty ? null : prefix));
    if (objects.isEmpty) {
      steps.skip('(no objects)');
      steps.summary();
      return;
    }
    final rows = <List<String>>[];
    for (final o in objects) {
      final size = o.size >= 1024 * 1024
          ? '${(o.size / (1024 * 1024)).toStringAsFixed(2)} MB'
          : o.size >= 1024
              ? '${(o.size / 1024).toStringAsFixed(1)} KB'
              : '${o.size} B';
      rows.add([cyan(o.key), size]);
    }
    table('${objects.length} objects', ['KEY', 'SIZE'], rows);
    steps.summary();
  });
}

class StorageDeleteCommand extends FlutterPatcherCommand {
  StorageDeleteCommand({this.config, this.backendOverride}) {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
    argParser.addMultiOption('key', help: 'Storage key to delete (repeatable).');
    argParser.addOption('uri', help: 'Full storage URI to delete.');
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete storage object(s) by key or full URI.';

  @override
  Future<int> run() => runGuarded(() async {
    final keys = (argResults!['key'] as List<String>?) ?? <String>[];
    final uri = argResults!['uri'] as String?;
    if (keys.isEmpty && (uri == null || uri.isEmpty)) {
      throw PackException(
        'Usage: flutter-ota storage delete --key <key> [--key <key>...] '
        '| --uri <storageUri>',
        64,
      );
    }
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('storage · delete');
    final steps = Steps('delete');
    if (keys.isNotEmpty) {
      await steps.run('Deleting ${keys.length} object(s)',
          () => backend.storage.deleteObjects(keys));
    } else {
      await steps.run('Deleting $uri', () => backend.storage.delete(uri!));
    }
    steps.summary();
  });
}
