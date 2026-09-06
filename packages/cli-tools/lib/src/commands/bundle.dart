import 'package:args/args.dart';
import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';

import '../ui/ui.dart';

/// `flutter_ota_kit bundle` — manage bundles entirely from the CLI (no direct
/// DB access needed; the CLI talks to the backend through its plugins).
class BundleCommand extends FlutterPatcherCommand {
  BundleCommand({this.config, this.backendOverride}) {
    addSubcommand(
      BundleListCommand(config: config, backendOverride: backendOverride),
    );
    addSubcommand(
      BundleShowCommand(config: config, backendOverride: backendOverride),
    );
    addSubcommand(
      BundleDeleteCommand(config: config, backendOverride: backendOverride),
    );
    addSubcommand(
      BundleDisableCommand(config: config, backendOverride: backendOverride),
    );
    addSubcommand(
      BundleEnableCommand(config: config, backendOverride: backendOverride),
    );
    addSubcommand(
      BundleForceCommand(config: config, backendOverride: backendOverride),
    );
    addSubcommand(
      BundlePromoteCommand(config: config, backendOverride: backendOverride),
    );
    addSubcommand(
      BundleUpdateCommand(config: config, backendOverride: backendOverride),
    );
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'bundle';

  @override
  String get description =>
      'Manage bundles (list / show / delete / disable / enable / force / promote).';

  @override
  Future<int> run() => runGuarded(() async {
    print(description);
    print('');
    print('Subcommands:');
    print(
      '  list                 List bundles (filters: --channel/-c, --platform/-p, --enabled, --limit/-l)',
    );
    print('  show --id <id>        Show a single bundle\'s details');
    print('  delete --id <id>      Delete a bundle');
    print('  disable --id <id>     Disable a bundle (stop serving it)');
    print('  enable --id <id>      Enable a bundle');
    print(
      '  force --id <id>       Force an update onto clients (--off to clear)',
    );
    print('  promote --id <id> -c  Promote a bundle to a channel');
    print(
      '  update --id <id> ...  Edit metadata (--message/--target-version/--enabled/--force)',
    );
  });
}

class BundleListCommand extends FlutterPatcherCommand {
  BundleListCommand({this.config, this.backendOverride}) {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
    argParser.addOption('channel', abbr: 'c', help: 'Filter by channel.');
    argParser.addOption('platform', abbr: 'p', help: 'Filter by platform.');
    argParser.addOption('enabled', help: 'Filter by enabled (true/false).');
    argParser.addOption('limit', abbr: 'l', defaultsTo: '20', help: 'Page size.');
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'list';

  @override
  String get description => 'List bundles.';

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
        ..add(kv('enabled', b.enabled ? green('yes') : yellow('no')))
        ..add(kv('platform', b.platform.value))
        ..add(kv('force', b.shouldForceUpdate ? green('yes') : yellow('no')))
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

class BundleShowCommand extends FlutterPatcherCommand {
  BundleShowCommand({this.config, this.backendOverride}) {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
    argParser.addOption('id', help: 'Bundle id.');
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'show';

  @override
  String get description => 'Show a single bundle\'s details.';

  @override
  Future<int> run() => runGuarded(() async {
    final id = argResults!['id'] as String?;
    if (id == null || id.isEmpty) {
      throw PackException('Usage: flutter_ota_kit bundle show --id <id>', 64);
    }
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('bundle · show');
    final b = await backend.db.getBundleById(id);
    if (b == null) {
      step('(not found)');
      return;
    }
    final lines = <String>[
      kv('id', cyan(b.id)),
      kv('channel', b.channel),
      kv('enabled', b.enabled ? green('yes') : yellow('no')),
      kv('platform', b.platform.value),
      kv('force', b.shouldForceUpdate ? green('yes') : yellow('no')),
      kv('target', b.targetAppVersion ?? b.fingerprintHash ?? dim('-')),
    ];
    if (b.message != null) lines.add(kv('message', b.message!));
    if (b.metadata?.signature != null) {
      lines.add(kv('signature', green('✓ signed')));
    }
    box('bundle', lines);
  });
}

class BundleDeleteCommand extends FlutterPatcherCommand {
  BundleDeleteCommand({this.config, this.backendOverride}) {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
    argParser.addOption('id', help: 'Bundle id.');
    argParser.addFlag(
      'keep-storage',
      help: 'Do not delete the storage object.',
      negatable: false,
    );
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete a bundle by id.';

  @override
  Future<int> run() => runGuarded(() async {
    final id = argResults!['id'] as String?;
    if (id == null || id.isEmpty) {
      throw PackException('Usage: flutter_ota_kit bundle delete --id <id>', 64);
    }
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('bundle · delete');
    final existing = await backend.db.getBundleById(id);
    if (existing == null) {
      throw StateError('Bundle "$id" not found.');
    }
    final keepStorage = argResults!['keep-storage'] as bool;
    await spinner(
      () => deleteBundle(backend, id),
      'Deleting bundle $id',
      done: 'Deleted',
    );
    if (!keepStorage && existing.storageUri.isNotEmpty) {
      await spinner(
        () => backend.storage.delete(existing.storageUri),
        'Removing storage object',
        done: 'Storage removed',
      );
    }
  });
}

class BundleDisableCommand extends FlutterPatcherCommand {
  BundleDisableCommand({this.config, this.backendOverride}) {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
    argParser.addOption('id', help: 'Bundle id.');
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'disable';

  @override
  String get description => 'Disable a bundle (stop serving it).';

  @override
  Future<int> run() => runGuarded(() async {
    final id = argResults!['id'] as String?;
    if (id == null || id.isEmpty) {
      throw PackException(
        'Usage: flutter_ota_kit bundle disable --id <id>',
        64,
      );
    }
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('bundle · disable');
    await spinner(
      () async {
        await backend.db.updateBundle(id, {'enabled': false});
        await backend.db.commitBundle();
      },
      'Disabling bundle $id',
      done: 'Disabled',
    );
  });
}

class BundleEnableCommand extends FlutterPatcherCommand {
  BundleEnableCommand({this.config, this.backendOverride}) {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
    argParser.addOption('id', help: 'Bundle id.');
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'enable';

  @override
  String get description => 'Enable a bundle.';

  @override
  Future<int> run() => runGuarded(() async {
    final id = argResults!['id'] as String?;
    if (id == null || id.isEmpty) {
      throw PackException('Usage: flutter_ota_kit bundle enable --id <id>', 64);
    }
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('bundle · enable');
    await spinner(
      () async {
        await backend.db.updateBundle(id, {'enabled': true});
        await backend.db.commitBundle();
      },
      'Enabling bundle $id',
      done: 'Enabled',
    );
  });
}

class BundleForceCommand extends FlutterPatcherCommand {
  BundleForceCommand({this.config, this.backendOverride}) {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
    argParser.addOption('id', help: 'Bundle id.');
    argParser.addFlag(
      'off',
      help: 'Clear the force-update flag instead of setting it.',
    );
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'force';

  @override
  String get description => 'Force an update onto clients (--off to clear).';

  @override
  Future<int> run() => runGuarded(() async {
    final id = argResults!['id'] as String?;
    if (id == null || id.isEmpty) {
      throw PackException(
        'Usage: flutter_ota_kit bundle force --id <id> [--off]',
        64,
      );
    }
    final off = argResults!['off'] as bool;
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('bundle · force');
    await spinner(
      () async {
        await backend.db.updateBundle(id, {
          'shouldForceUpdate': !off,
          if (!off) 'enabled': true,
        });
        await backend.db.commitBundle();
      },
      off ? 'Clearing force flag on $id' : 'Forcing update for $id',
      done: off ? 'Cleared' : 'Forced',
    );
  });
}

class BundlePromoteCommand extends FlutterPatcherCommand {
  BundlePromoteCommand({this.config, this.backendOverride}) {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
    argParser.addOption('id', help: 'Bundle id.');
    argParser.addOption('channel', abbr: 'c', help: 'Target channel.');
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'promote';

  @override
  String get description => 'Promote a bundle to a channel.';

  @override
  Future<int> run() => runGuarded(() async {
    final id = argResults!['id'] as String?;
    final channel = argResults!['channel'] as String?;
    if (id == null || id.isEmpty || channel == null || channel.isEmpty) {
      throw PackException(
        'Usage: flutter_ota_kit bundle promote --id <id> --channel <channel>',
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
    box('promote', [kv('bundle', cyan(id)), kv('channel', channel)]);
  });
}

class BundleUpdateCommand extends FlutterPatcherCommand {
  BundleUpdateCommand({this.config, this.backendOverride}) {
    argParser.addOption('backend', abbr: 'b', help: 'Backend provider.');
    argParser.addOption('id', help: 'Bundle id.');
    argParser.addOption('message', abbr: 'm', help: 'New release message.');
    argParser.addOption('target-version', help: 'New target app version (e.g. 1.0.0).');
    argParser.addOption('enabled', help: 'Set enabled (true/false).');
    argParser.addOption('force', abbr: 'f', help: 'Set force-update (true/false).');
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'update';

  @override
  String get description =>
      'Edit a bundle\'s metadata (message / target version / enabled / force).';

  @override
  Future<int> run() => runGuarded(() async {
    final id = argResults!['id'] as String?;
    if (id == null || id.isEmpty) {
      throw PackException(
        'Usage: flutter-ota bundle update --id <id> '
        '[--message <m>] [--target-version <v>] [--enabled true|false] '
        '[--force true|false]',
        64,
      );
    }
    final patch = <String, Object?>{};
    final message = argResults!['message'] as String?;
    if (message != null) patch['message'] = message;
    final target = argResults!['target-version'] as String?;
    if (target != null) patch['targetAppVersion'] = target;
    final enabled = argResults!['enabled'] as String?;
    if (enabled != null) {
      patch['enabled'] = enabled == 'true' || enabled == '1';
    }
    final force = argResults!['force'] as String?;
    if (force != null) {
      patch['shouldForceUpdate'] = force == 'true' || force == '1';
    }
    if (patch.isEmpty) {
      throw PackException('Nothing to update — pass at least one flag.', 64);
    }
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('bundle · update');
    await spinner(
      () async {
        await backend.db.updateBundle(id, patch);
        await backend.db.commitBundle();
      },
      'Updating $id',
      done: 'Updated',
    );
    final b = await backend.db.getBundleById(id);
    if (b != null) {
      box('bundle', [
        kv('id', cyan(b.id)),
        kv('enabled', b.enabled ? green('yes') : yellow('no')),
        kv('force', b.shouldForceUpdate ? green('yes') : yellow('no')),
        kv('target', b.targetAppVersion ?? dim('-')),
        if (b.message != null) kv('message', b.message!),
      ]);
    }
  });
}
