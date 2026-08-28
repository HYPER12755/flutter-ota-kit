import 'dart:io';

import 'package:args/args.dart';

import '../backend.dart';
import '../cli_base.dart';
import '../config.dart';
import '../operations.dart';
import '../ui/ui.dart';
import '../util.dart';

/// `flutter_patcher deploy` — zip + upload + register a new bundle.
class DeployCommand extends FlutterPatcherCommand {
  DeployCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'deploy';

  @override
  String get description =>
      'Zip a source directory, upload it, and register a new bundle.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('backend',
        abbr: 'b', help: 'Backend provider (supabase/postgres/cloudflare/aws).')
    ..addOption('source', abbr: 's', help: 'Source directory to zip + upload.')
    ..addOption('channel', abbr: 'c', help: 'Target channel.')
    ..addOption('platform', abbr: 'p', defaultsTo: 'android', help: 'Platform.')
    ..addOption('message', abbr: 'm', help: 'Release message.')
    ..addFlag('force', help: 'Force the update on clients.')
    ..addOption('target-app-version',
        help: 'Semver range target (XOR with fingerprint-hash).')
    ..addOption('fingerprint-hash',
        help: 'Fingerprint hash target (XOR with target-app-version).')
    ..addOption('key', help: 'Path to Ed25519 private key file (sign bundle).')
    ..addOption('git-commit-hash', help: 'Git commit hash (auto-detected).')
    ..addOption('bundle-id', help: 'Explicit bundle id (uuidv7 by default).');

  @override
  Future<int> run() => runGuarded(() async {
        final cfg = effectiveConfig(config ?? loadConfig(), argResults!);
        final backend = requireBackend(cfg, override: backendOverride);
        final source = argResults!['source'] as String? ?? cfg?.source ?? './dist';
        final channel =
            argResults!['channel'] as String? ?? cfg?.channel ?? 'production';
        final platform =
            argResults!['platform'] as String? ?? cfg?.platform ?? 'android';
        final message = argResults!['message'] as String?;
        final force = argResults!['force'] as bool;
        final targetAppVersion = argResults!['target-app-version'] as String?;
        final fingerprintHash = argResults!['fingerprint-hash'] as String?;
        final keyPath = argResults!['key'] as String?;
        String? signingKey;
        if (keyPath != null) signingKey = File(keyPath).readAsStringSync().trim();
        final resolvedGitCommitHash =
            argResults!['git-commit-hash'] as String? ?? await gitCommitHash(source);
        final bundleId = argResults!['bundle-id'] as String?;

        banner('deploy');
        stdout.writeln(
          '${gray('channel')}  ${cyan(channel)}   '
          '${gray('platform')}  ${cyan(platform)}   '
          '${gray('source')}  ${dim(source)}',
        );
        final bundle = await spinner(
          () => deployBundle(
            backend,
            DeployOptions(
              source: source,
              channel: channel,
              platform: platform,
              message: message,
              force: force,
              targetAppVersion: targetAppVersion,
              fingerprintHash: fingerprintHash,
              signingKeyBase64: signingKey,
              gitCommitHash: resolvedGitCommitHash,
              bundleId: bundleId,
            ),
          ),
          'Uploading & registering bundle',
          done: 'Bundle deployed',
        );

        final lines = <String>[
          kv('bundle id', cyan(bundle.id)),
          kv('channel', bundle.channel),
          kv('platform', bundle.platform.value),
          kv('enabled', bundle.enabled ? green('true') : yellow('false')),
          kv('storage uri', gray(bundle.storageUri)),
        ];
        if (bundle.targetAppVersion != null) {
          lines.add(kv('target app', bundle.targetAppVersion!));
        }
        if (bundle.fingerprintHash != null) {
          lines.add(kv('fingerprint', bundle.fingerprintHash!));
        }
        if (bundle.gitCommitHash != null) {
          lines.add(kv('git commit', bundle.gitCommitHash!));
        }
        if (bundle.message != null) lines.add(kv('message', bundle.message!));
        if (bundle.metadata?.signature != null) {
          lines.add(kv('signature', dim('✓ signed')));
        }
        box('deployed', lines);
      });
}
