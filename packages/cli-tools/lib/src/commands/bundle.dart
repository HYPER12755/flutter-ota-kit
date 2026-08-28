import 'package:args/args.dart';
import 'package:flutter_patcher_cli/flutter_patcher_cli.dart';

import '../ui/ui.dart';

/// `flutter_patcher bundle` — manage bundles.
class BundleCommand extends FlutterPatcherCommand {
  BundleCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'bundle';

  @override
  String get description => 'Manage bundles (list / delete / promote).';

  @override
  Future<int> run() => runGuarded(() async {
        print(description);
        print('');
        print('Subcommands:');
        print('  list                List bundles');
        print('  delete <id>         Delete a bundle');
        print('  promote <id> -c <c> Promote a bundle to a channel');
      });
}

class BundleListCommand extends FlutterPatcherCommand {
  BundleListCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'list';

  @override
  String get description => 'List bundles.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Backend provider.')
    ..addOption('channel', abbr: 'c', help: 'Filter by channel.')
    ..addOption('platform', abbr: 'p', help: 'Filter by platform.')
    ..addOption('enabled', help: 'Filter by enabled (true/false).')
    ..addOption('limit', abbr: 'l', defaultsTo: '20', help: 'Page size.');

  @override
  Future<int> run() => runGuarded(() async {
        final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
        final backend = requireBackend(cfg, override: backendOverride);
        final enabledRaw = argResults!['enabled'] as String?;
        final enabled = enabledRaw == null
            ? null
            : (enabledRaw == 'true' || enabledRaw == '1');
        final res = await listBundles(
          backend,
          ListOptions(
            channel: argResults!['channel'] as String?,
            platform: argResults!['platform'] as String?,
            enabled: enabled,
            limit: int.parse(argResults!['limit'] as String),
          ),
        );
        banner('bundle · list');
        if (res.data.isEmpty) {
          step('(no bundles)');
          return;
        }
        final lines = <String>[];
        for (var i = 0; i < res.data.length; i++) {
          final b = res.data[i];
          final target = b.targetAppVersion ?? b.fingerprintHash ?? dim('-');
          lines
            ..add(kv('#$i', cyan(b.id)))
            ..add(kv('channel', b.channel))
            ..add(kv(
              'enabled',
              b.enabled ? green('yes') : yellow('no'),
            ))
            ..add(kv('platform', b.platform.value))
            ..add(kv('target', target));
          if (b.message != null) lines.add(kv('message', b.message!));
          if (b.metadata?.signature != null) {
            lines.add(kv('signature', green('✓ signed')));
          }
          lines.add('');
        }
        box('${res.data.length} bundles', lines);
        step('total: ${res.pagination.total}');
      });
}

class BundleDeleteCommand extends FlutterPatcherCommand {
  BundleDeleteCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete a bundle by id.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Backend provider.')
    ..addOption('id', help: 'Bundle id.');

  @override
  Future<int> run() => runGuarded(() async {
        final id = argResults!['id'] as String?;
        if (id == null || id.isEmpty) {
          throw PackException('Usage: flutter_patcher bundle delete --id <id>', 64);
        }
        final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
        final backend = requireBackend(cfg, override: backendOverride);
        banner('bundle · delete');
        await spinner(
          () => deleteBundle(backend, id),
          'Deleting bundle $id',
          done: 'Deleted',
        );
      });
}

class BundlePromoteCommand extends FlutterPatcherCommand {
  BundlePromoteCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'promote';

  @override
  String get description => 'Promote a bundle to a channel.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Backend provider.')
    ..addOption('id', help: 'Bundle id.')
    ..addOption('channel', abbr: 'c', help: 'Target channel.');

  @override
  Future<int> run() => runGuarded(() async {
        final id = argResults!['id'] as String?;
        final channel = argResults!['channel'] as String?;
        if (id == null || id.isEmpty || channel == null || channel.isEmpty) {
          throw PackException(
            'Usage: flutter_patcher bundle promote --id <id> --channel <channel>',
            64,
          );
        }
        final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
        final backend = requireBackend(cfg, override: backendOverride);
        banner('bundle · promote');
        await spinner(
          () => promoteBundle(backend, id, channel),
          'Promoting $id to $channel',
          done: 'Promoted',
        );
        box('promote', [
          kv('bundle', cyan(id)),
          kv('channel', channel),
        ]);
      });
}
