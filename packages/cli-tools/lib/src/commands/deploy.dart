import 'dart:io';

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';

import '../backend.dart';
import '../cli_base.dart';
import '../config.dart';
import '../operations.dart';
import '../ui/ui.dart';
import '../util.dart';

/// `flutter-ota deploy` — zip + upload + register a new bundle.
class DeployCommand extends FlutterPatcherCommand {
  DeployCommand({this.config, this.backendOverride}) {
    argParser.addOption(
      'backend',
      abbr: 'b',
      help: 'Backend provider (supabase/postgres/cloudflare/aws).',
    );
    argParser.addOption('source', abbr: 's', help: 'Source directory to zip + upload.');
    argParser.addOption('channel', abbr: 'c', help: 'Target channel.');
    argParser.addOption('platform', abbr: 'p', defaultsTo: 'android', help: 'Platform.');
    argParser.addOption('message', abbr: 'm', help: 'Release message.');
    argParser.addFlag('force', abbr: 'f', help: 'Force the update on clients.');
    argParser.addOption(
      'target-app-version',
      help: 'Semver range target (XOR with fingerprint-hash).',
    );
    argParser.addOption(
      'fingerprint-hash',
      help: 'Fingerprint hash target (XOR with target-app-version).',
    );
    argParser.addOption(
      'key',
      abbr: 'k',
      help: 'Path to Ed25519 private key file (sign bundle).',
    );
    argParser.addOption('git-commit-hash', help: 'Git commit hash (auto-detected).');
    argParser.addOption(
      'bundle-id',
      abbr: 'i',
      help: 'Explicit bundle id (uuidv7 by default).',
    );
  }

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'deploy';

  @override
  String get description =>
      'Zip a source directory, upload it, and register a new bundle.';

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
        argResults!['git-commit-hash'] as String? ??
        await gitCommitHash(source);
    final bundleId = argResults!['bundle-id'] as String?;

    banner('deploy');
    info('channel ${cyan(channel)}  platform ${cyan(platform)}  source ${dim(source)}');

    final steps = Steps('deploy');
    final bundle = await _deployWithPhases(steps, backend, source, channel,
        platform, message, force, targetAppVersion, fingerprintHash,
        signingKey, resolvedGitCommitHash, bundleId);
    steps.summary();

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

/// Deploy with per-phase UI. Each phase reported by `DeployOptions.onPhase`
/// is shown as an active spinner line that gets replaced in-place.
Future<Bundle> _deployWithPhases(
  Steps steps,
  Backend backend,
  String source,
  String channel,
  String platform,
  String? message,
  bool force,
  String? targetAppVersion,
  String? fingerprintHash,
  String? signingKey,
  String? resolvedGitCommitHash,
  String? bundleId,
) async {
  String? activeLabel;
  try {
    final bundle = await deployBundle(
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
        onPhase: (phase) {
          if (activeLabel != null) {
            steps.completeActive();
          }
          activeLabel = phase;
          steps.startActive(phase);
        },
      ),
    );
    if (activeLabel != null) {
      steps.completeActive();
      activeLabel = null;
    }
    return bundle;
  } catch (e) {
    if (activeLabel != null) {
      steps.completeActive(success: false);
      activeLabel = null;
    }
    rethrow;
  }
}
