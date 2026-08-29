import 'package:args/args.dart';
import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';

import '../ui/ui.dart';

/// `flutter_ota_kit channel` — manage channels.
class ChannelCommand extends FlutterPatcherCommand {
  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  ChannelCommand({this.config, this.backendOverride}) {
    addSubcommand(ChannelListCommand(config: config, backendOverride: backendOverride));
    addSubcommand(ChannelGetCommand(config: config, backendOverride: backendOverride));
    addSubcommand(ChannelSetCommand(config: config, backendOverride: backendOverride));
  }

  @override
  String get name => 'channel';

  @override
  String get description => 'Manage channels (list / get / set).';

  @override
  Future<int> run() => runGuarded(() async {
        print(description);
        print('');
        print('Subcommands:');
        print('  list              List channels');
        print('  get <channel>     Show the live bundle for a channel');
        print('  set <c> <id>      Promote a bundle to a channel');
      });
}

class ChannelListCommand extends FlutterPatcherCommand {
  ChannelListCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'list';

  @override
  String get description => 'List channels.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Backend provider.');

  @override
  Future<int> run() => runGuarded(() async {
        final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
        final backend = requireBackend(cfg, override: backendOverride);
        banner('channel · list');
        final channels = await listChannels(backend);
        if (channels.isEmpty) {
          step('(no channels)');
          return;
        }
        box('${channels.length} channels', channels.map((c) => '  $c').toList());
      });
}

class ChannelGetCommand extends FlutterPatcherCommand {
  ChannelGetCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'get';

  @override
  String get description => 'Show the live (enabled) bundle for a channel.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Backend provider.')
    ..addOption('channel', abbr: 'c', help: 'Channel.');

  @override
  Future<int> run() => runGuarded(() async {
        final channel = argResults!['channel'] as String?;
        if (channel == null || channel.isEmpty) {
          throw PackException('Usage: flutter_ota_kit channel get --channel <channel>', 64);
        }
        final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
        final backend = requireBackend(cfg, override: backendOverride);
        banner('channel · get');
        final bundle = await getChannel(backend, channel);
        if (bundle == null) {
          err('no live bundle on channel "$channel"');
          return;
        }
        box('channel "$channel"', [
          kv('live bundle', cyan(bundle.id)),
          kv('platform', bundle.platform.value),
          kv('enabled', bundle.enabled ? green('yes') : yellow('no')),
          kv('target', bundle.targetAppVersion ?? bundle.fingerprintHash ?? dim('-')),
          if (bundle.message != null) kv('message', bundle.message!),
        ]);
      });
}

class ChannelSetCommand extends FlutterPatcherCommand {
  ChannelSetCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'set';

  @override
  String get description => 'Promote a bundle to a channel.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Backend provider.')
    ..addOption('channel', abbr: 'c', help: 'Channel.')
    ..addOption('bundle-id', abbr: 'i', help: 'Bundle id.');

  @override
  Future<int> run() => runGuarded(() async {
        final channel = argResults!['channel'] as String?;
        final bundleId = argResults!['bundle-id'] as String?;
        if (channel == null ||
            channel.isEmpty ||
            bundleId == null ||
            bundleId.isEmpty) {
          throw PackException(
            'Usage: flutter_ota_kit channel set --channel <c> --bundle-id <id>',
            64,
          );
        }
        final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
        final backend = requireBackend(cfg, override: backendOverride);
        banner('channel · set');
        await spinner(
          () => promoteBundle(backend, bundleId, channel),
          'Promoting $bundleId to $channel',
          done: 'Channel set',
        );
        box('channel set', [
          kv('channel', channel),
          kv('bundle', cyan(bundleId)),
        ]);
      });
}
