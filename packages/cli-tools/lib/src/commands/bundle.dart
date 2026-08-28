import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../backend.dart';
import '../cli_base.dart';
import '../config.dart';
import '../operations.dart';

/// `flutter_patcher bundle` — manage bundles.
class BundleCommand extends Command<int> {
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

class BundleListCommand extends Command<int> {
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
        if (res.data.isEmpty) {
          stdout.writeln('(no bundles)');
          return;
        }
        stdout.writeln('id                                   channel      '
            'enabled platform target');
        for (final b in res.data) {
          final target = b.targetAppVersion ?? b.fingerprintHash ?? '-';
          stdout.writeln('${b.id}  ${b.channel.padRight(12)}  '
              '${(b.enabled ? 'yes' : 'no').padRight(7)} '
              '${b.platform.value.padRight(7)} $target');
        }
        stdout.writeln('');
        stdout.writeln('total: ${res.pagination.total}');
      });
}

class BundleDeleteCommand extends Command<int> {
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
          throw StateError('Usage: flutter_patcher bundle delete <id>');
        }
        final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
        final backend = requireBackend(cfg, override: backendOverride);
        await deleteBundle(backend, id);
        stdout.writeln('Deleted bundle $id');
      });
}

class BundlePromoteCommand extends Command<int> {
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
          throw StateError(
            'Usage: flutter_patcher bundle promote <id> --channel <channel>',
          );
        }
        final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
        final backend = requireBackend(cfg, override: backendOverride);
        await promoteBundle(backend, id, channel);
        stdout.writeln('Promoted bundle $id to channel $channel');
      });
}
