import 'package:args/args.dart';
import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';

import '../ui/ui.dart';

/// `flutter_ota_kit storage` — inspect and clean the blob storage bucket
/// directly from the CLI (no need to open the provider dashboard).
class StorageCommand extends FlutterPatcherCommand {
  StorageCommand({this.config, this.backendOverride}) {
    addSubcommand(StorageListCommand(config: config, backendOverride: backendOverride));
    addSubcommand(StorageDeleteCommand(config: config, backendOverride: backendOverride));
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
  StorageListCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'list';

  @override
  String get description => 'List storage objects.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Backend provider.')
    ..addOption('prefix', help: 'Key prefix filter (e.g. bundles).');

  @override
  Future<int> run() => runGuarded(() async {
        final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
        final backend = requireBackend(cfg, override: backendOverride);
        final prefix = argResults!['prefix'] as String?;
        banner('storage · list');
        final objects = await backend.storage.listObjects(
          prefix == null || prefix.isEmpty ? null : prefix,
        );
        if (objects.isEmpty) {
          step('(no objects)');
          return;
        }
        final lines = <String>[];
        for (final o in objects) {
          final size = o.size >= 1024 * 1024
              ? '${(o.size / (1024 * 1024)).toStringAsFixed(2)} MB'
              : o.size >= 1024
                  ? '${(o.size / 1024).toStringAsFixed(1)} KB'
                  : '${o.size} B';
          lines
            ..add(kv('key', cyan(o.key)))
            ..add(kv('size', size))
            ..add('');
        }
        box('${objects.length} objects', lines);
      });
}

class StorageDeleteCommand extends FlutterPatcherCommand {
  StorageDeleteCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete storage object(s) by key or full URI.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Backend provider.')
    ..addMultiOption('key', help: 'Storage key to delete (repeatable).')
    ..addOption('uri', help: 'Full storage URI to delete.');

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
        if (keys.isNotEmpty) {
          await spinner(
            () => backend.storage.deleteObjects(keys),
            'Deleting ${keys.length} object(s)',
            done: 'Deleted',
          );
        } else {
          await spinner(
            () => backend.storage.delete(uri!),
            'Deleting $uri',
            done: 'Deleted',
          );
        }
      });
}
