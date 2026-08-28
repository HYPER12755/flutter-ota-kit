import 'package:flutter_patcher_cli/flutter_patcher_cli.dart';

import '../ui/ui.dart';

/// `flutter_patcher build` — package a release APK into a device-compatible
/// OTA patch (`dist/patch.zip`) that the `deploy` command can publish.
///
/// Includes every ABI found in the APK so a single bundle installs on all
/// device architectures.
class BuildCommand extends FlutterPatcherCommand {
  BuildCommand() {
    argParser
      ..addOption(
        'apk',
        abbr: 'a',
        help: 'Path to the release APK to extract libapp.so and assets from.',
      )
      ..addMultiOption(
        'assets',
        help: 'Asset keys to include as overlay updates (repeatable).',
      )
      ..addOption(
        'version',
        help: 'Patch version string (stored in manifest.version).',
      )
      ..addOption(
        'target-version-code',
        help: 'Host APK versionCode this patch targets (integer).',
      )
      ..addOption(
        'abi',
        help: 'Preferred ABI to report (default: all ABIs found in APK).',
      )
      ..addOption(
        'out',
        abbr: 'o',
        defaultsTo: 'dist',
        help: 'Output directory for patch.zip and manifest.json.',
      );
  }

  @override
  String get name => 'build';

  @override
  String get description =>
      'Build a device-compatible OTA patch (patch.zip) from a release APK.';

  @override
  Future<int> run() => runGuarded(() async {
        final results = argResults!;
        final apk = results['apk'] as String?;
        if (apk == null || apk.isEmpty) {
          throw PackException('missing required --apk <path>', 64);
        }
        final version = results['version'] as String?;
        if (version == null || version.isEmpty) {
          throw PackException('missing required --version <string>', 64);
        }
        final targetVersionCodeRaw = results['target-version-code'] as String?;
        if (targetVersionCodeRaw == null || targetVersionCodeRaw.isEmpty) {
          throw PackException('missing required --target-version-code <int>', 64);
        }
        final targetVersionCode = int.tryParse(targetVersionCodeRaw);
        if (targetVersionCode == null) {
          throw PackException('--target-version-code must be an integer', 64);
        }

        banner('build');
        final bar = ProgressBar(1, 'pack');
        final result = await packPatch(
          apkPath: apk,
          version: version,
          targetVersionCode: targetVersionCode,
          abi: results['abi'] as String?,
          requestedAssets: results['assets'] as List<String>,
          out: results['out'] as String,
          onProgress: (done, total, label) {
            bar.total = total;
            bar.update(done, label);
          },
        );

        box('patch.zip', [
          kv('version', result.version),
          kv('target code', result.targetVersionCode.toString()),
          kv('abis', cyan(result.abis.join('  ·  '))),
          kv('bundle md5', gray(result.md5)),
          kv('overlay assets', result.assetCount.toString()),
          kv('payload', result.payloadPath),
          kv('manifest', result.manifestPath),
        ]);
        step('Build complete — ready to deploy.');
      });
}
