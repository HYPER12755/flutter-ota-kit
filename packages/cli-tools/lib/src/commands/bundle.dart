import 'dart:io';

import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';

import '../ui/ui.dart';

final _uuidRe = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

void _requireUuid(String? id, String command) {
  if (id == null || id.isEmpty) {
    throw PackException('Usage: flutter-ota bundle $command --id <id>', 64);
  }
  if (!_uuidRe.hasMatch(id)) {
    throw PackException(
      'Invalid UUID format: "$id". '
      'Expected: 8-4-4-4-12 hex digits.',
      64,
    );
  }
}

/// `flutter-ota bundle` — manage bundles entirely from the CLI (no direct
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
      'Manage bundles (list / show / delete / disable / enable / force / promote / update).';
}

class BundleListCommand extends FlutterPatcherCommand {
  BundleListCommand({this.config, this.backendOverride}) {
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption('backend', abbr: 'b', help: detected != null
        ? 'Backend provider [detected: $detected].'
        : 'Backend provider.');
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
    final limitRaw = argResults!['limit'] as String;
    final limit = int.tryParse(limitRaw);
    if (limit == null || limit < 1) {
      throw PackException('--limit must be a positive integer (got "$limitRaw")', 64);
    }
    final res = await listBundles(
      backend,
      ListOptions(
        channel: argResults!['channel'] as String?,
        platform: argResults!['platform'] as String?,
        enabled: enabled,
        limit: limit,
      ),
    );
    banner('bundle · list');
    if (res.data.isEmpty) {
      step('(no bundles)');
      return;
    }
    final rows = <List<String>>[];
    for (var i = 0; i < res.data.length; i++) {
      final b = res.data[i];
      final enabled = b.enabled ? green('✓') : red('✗');
      final force = b.shouldForceUpdate ? green('✓') : dim('✗');
      rows.add([
        '$i',
        cyan(b.id),
        b.channel,
        b.platform.value,
        force,
        enabled,
      ]);
    }
    table(
      '${res.data.length} bundles (total: ${res.pagination.total})',
      ['#', 'ID', 'CHANNEL', 'PLAT', 'FORCE', 'ON'],
      rows,
    );
  });
}

class BundleShowCommand extends FlutterPatcherCommand {
  BundleShowCommand({this.config, this.backendOverride}) {
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption('backend', abbr: 'b', help: detected != null ? 'Backend provider [detected: $detected].' : 'Backend provider.');
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
    _requireUuid(id, 'show');
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('bundle · show');
    final b = await backend.db.getBundleById(id!);
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
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption('backend', abbr: 'b', help: detected != null ? 'Backend provider [detected: $detected].' : 'Backend provider.');
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
    _requireUuid(id, 'delete');
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('bundle · delete');
    final existing = await backend.db.getBundleById(id!);
    if (existing == null) {
      throw StateError('Bundle "$id" not found.');
    }
    final keepStorage = argResults!['keep-storage'] as bool;
    final steps = Steps('delete');
    await steps.run('Deleting bundle $id', () => deleteBundle(backend, id));
    if (!keepStorage && existing.storageUri.isNotEmpty) {
      await steps.run('Removing storage object',
          () => backend.storage.delete(existing.storageUri));
    }
    steps.summary();
  });
}

class BundleDisableCommand extends FlutterPatcherCommand {
  BundleDisableCommand({this.config, this.backendOverride}) {
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption('backend', abbr: 'b', help: detected != null ? 'Backend provider [detected: $detected].' : 'Backend provider.');
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
    _requireUuid(id, 'disable');
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('bundle · disable');
    final steps = Steps('disable');
    await steps.run('Disabling bundle $id', () async {
      await backend.db.updateBundle(id!, {'enabled': false});
      await backend.db.commitBundle();
    });
    steps.summary();
  });
}

class BundleEnableCommand extends FlutterPatcherCommand {
  BundleEnableCommand({this.config, this.backendOverride}) {
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption('backend', abbr: 'b', help: detected != null ? 'Backend provider [detected: $detected].' : 'Backend provider.');
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
    _requireUuid(id, 'enable');
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('bundle · enable');
    final steps = Steps('enable');
    await steps.run('Enabling bundle $id', () async {
      await backend.db.updateBundle(id!, {'enabled': true});
      await backend.db.commitBundle();
    });
    steps.summary();
  });
}

class BundleForceCommand extends FlutterPatcherCommand {
  BundleForceCommand({this.config, this.backendOverride}) {
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption('backend', abbr: 'b', help: detected != null ? 'Backend provider [detected: $detected].' : 'Backend provider.');
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
    _requireUuid(id, 'force');
    final off = argResults!['off'] as bool;
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('bundle · force');
    final steps = Steps('force');
    await steps.run(
      off ? 'Clearing force flag on $id' : 'Forcing update for $id',
      () async {
        await backend.db.updateBundle(id!, {
          'shouldForceUpdate': !off,
          if (!off) 'enabled': true,
        });
        await backend.db.commitBundle();
      },
    );
    steps.summary();
  });
}

class BundlePromoteCommand extends FlutterPatcherCommand {
  BundlePromoteCommand({this.config, this.backendOverride}) {
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption('backend', abbr: 'b', help: detected != null ? 'Backend provider [detected: $detected].' : 'Backend provider.');
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
    _requireUuid(id, 'promote');
    if (channel == null || channel.isEmpty) {
      throw PackException(
        'Usage: flutter-ota bundle promote --id <id> --channel <channel>',
        64,
      );
    }
    final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
    final backend = requireBackend(cfg, override: backendOverride);
    banner('bundle · promote');
    final steps = Steps('promote');
    await steps.run('Promoting $id to $channel',
        () => promoteBundle(backend, id!, channel));
    steps.summary();
    stdout.writeln('  ${dim('→')} bundle ${cyan(id!)} → channel ${cyan(channel)}');
  });
}

class BundleUpdateCommand extends FlutterPatcherCommand {
  BundleUpdateCommand({this.config, this.backendOverride}) {
    final detected = config?.provider ?? loadConfig()?.provider;
    argParser.addOption('backend', abbr: 'b', help: detected != null ? 'Backend provider [detected: $detected].' : 'Backend provider.');
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
    _requireUuid(id, 'update');
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
    final steps = Steps('update');
    await steps.run('Updating $id', () async {
      await backend.db.updateBundle(id!, patch);
      await backend.db.commitBundle();
    });
    final b = await backend.db.getBundleById(id!);
    steps.summary();
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
