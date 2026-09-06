import 'package:args/args.dart';
import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';
import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';

import '../ui/ui.dart';

/// `flutter_ota_kit rollback` — roll a channel back to a previous bundle.
class RollbackCommand extends FlutterPatcherCommand {
  RollbackCommand({this.config, this.backendOverride}) {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
    argParser.addOption('channel', abbr: 'c', help: 'Channel to roll back.');
    argParser.addOption(
      'bundle-id',
      abbr: 'i',
      help: 'Roll back to this specific bundle id.',
    );
    argParser.addOption('platform', abbr: 'p', help: 'Platform filter (e.g. android).');
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'rollback';

  @override
  String get description =>
      'Roll a channel back: disable the latest enabled bundle (or a specific --bundle-id).';

  @override
  Future<int> run() => runGuarded(() async {
    final channel = argResults!['channel'] as String?;
    if (channel == null || channel.isEmpty) {
      throw PackException(
        'Usage: flutter_ota_kit rollback --channel <channel> [--bundle-id <id>]',
        64,
      );
    }
    final bundleId = argResults!['bundle-id'] as String?;
    final platformRaw = argResults!['platform'] as String?;
    final platform = platformRaw == null
        ? null
        : Platform.fromValue(platformRaw);

    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);

    banner('rollback');
    final (disabled, live) = await spinner(
      () async {
        if (bundleId != null && bundleId.isNotEmpty) {
          return rollbackToBundle(
            backend,
            channel,
            bundleId,
            platform: platform,
          );
        }
        final id = await rollbackChannel(backend, channel);
        final nowLive = (await getChannel(backend, channel))?.id ?? '';
        return (<String>[id], nowLive);
      },
      'Rolling back channel "$channel"',
      done: 'Rolled back',
    );
    box('rollback', [
      kv('channel', channel),
      kv('now live', cyan(live)),
      kv('disabled', disabled.isEmpty ? dim('(none)') : disabled.join(', ')),
    ]);
  });
}
