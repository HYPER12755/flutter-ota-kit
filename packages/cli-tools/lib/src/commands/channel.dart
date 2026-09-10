import 'dart:io';

import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';

import '../ui/ui.dart';

/// `flutter-ota channel` — manage channels.
class ChannelCommand extends FlutterPatcherCommand {
  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  ChannelCommand({this.config, this.backendOverride}) {
    addSubcommand(
      ChannelListCommand(config: config, backendOverride: backendOverride),
    );
    addSubcommand(
      ChannelGetCommand(config: config, backendOverride: backendOverride),
    );
    addSubcommand(
      ChannelSetCommand(config: config, backendOverride: backendOverride),
    );
  }

  @override
  String get name => 'channel';

  @override
  String get description => 'Manage channels (list / get / set).';
}

class ChannelListCommand extends FlutterPatcherCommand {
  ChannelListCommand({this.config, this.backendOverride}) {
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption(
      'backend',
      abbr: 'b',
      help: detected != null
          ? 'Backend provider [detected: $detected].'
          : 'Backend provider.',
    );
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'list';

  @override
  String get description => 'List channels.';

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
  ChannelGetCommand({this.config, this.backendOverride}) {
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption(
      'backend',
      abbr: 'b',
      help: detected != null
          ? 'Backend provider [detected: $detected].'
          : 'Backend provider.',
    );
    argParser.addOption('channel', abbr: 'c', help: 'Channel.');
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'get';

  @override
  String get description => 'Show the live (enabled) bundle for a channel.';

  @override
  Future<int> run() => runGuarded(() async {
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final channel = argResults!['channel'] as String? ?? cfg?.channel;
    if (channel == null || channel.isEmpty) {
      throw PackException(
        'Usage: flutter-ota channel get --channel <channel>',
        64,
      );
    }
    final backend = requireBackend(cfg, override: backendOverride);
    banner('channel · get');
    final bundle = await getChannel(backend, channel);
    if (bundle == null) {
      throw StateError('no live bundle on channel "$channel"');
    }
    box('channel "$channel"', [
      kv('live bundle', cyan(bundle.id)),
      kv('platform', bundle.platform.value),
      kv('enabled', bundle.enabled ? green('yes') : yellow('no')),
      kv(
        'target',
        bundle.targetAppVersion ?? bundle.fingerprintHash ?? dim('-'),
      ),
      if (bundle.message != null) kv('message', bundle.message!),
    ]);
  });
}

class ChannelSetCommand extends FlutterPatcherCommand {
  ChannelSetCommand({this.config, this.backendOverride}) {
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption(
      'backend',
      abbr: 'b',
      help: detected != null
          ? 'Backend provider [detected: $detected].'
          : 'Backend provider.',
    );
    argParser.addOption('channel', abbr: 'c', help: 'Channel.');
    argParser.addOption('bundle-id', abbr: 'i', help: 'Bundle id.');
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'set';

  @override
  String get description => 'Set the active bundle for a channel.';

  @override
  Future<int> run() => runGuarded(() async {
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final channel = argResults!['channel'] as String? ?? cfg?.channel;
    final bundleId = argResults!['bundle-id'] as String?;
    if (channel == null ||
        channel.isEmpty ||
        bundleId == null ||
        bundleId.isEmpty) {
      throw PackException(
        'Usage: flutter-ota channel set --channel <c> --bundle-id <id>',
        64,
      );
    }
    final backend = requireBackend(cfg, override: backendOverride);
    banner('channel · set');
    final steps = Steps('set');
    await steps.run(
      'Promoting $bundleId to $channel',
      () => promoteBundle(backend, bundleId, channel),
    );
    steps.summary();
    stdout.writeln(
      '  ${dim('→')} channel ${cyan(channel)} = ${cyan(bundleId)}',
    );
  });
}
