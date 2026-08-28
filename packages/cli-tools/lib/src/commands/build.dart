import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_patcher_cli/flutter_patcher_cli.dart';

/// `flutter_patcher build` — package a release APK into a device-compatible
/// OTA patch (`dist/patch.zip`) that the `deploy` command can publish.
///
/// Includes every ABI found in the APK so a single bundle installs on all
/// device architectures.
class BuildCommand extends Command<int> {
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
  Future<int> run() async {
    final results = argResults!;
    final apk = results['apk'] as String?;
    if (apk == null || apk.isEmpty) {
      stderr.writeln('error: missing required --apk <path>');
      return 64;
    }
    final version = results['version'] as String?;
    if (version == null || version.isEmpty) {
      stderr.writeln('error: missing required --version <string>');
      return 64;
    }
    final targetVersionCodeRaw = results['target-version-code'] as String?;
    if (targetVersionCodeRaw == null || targetVersionCodeRaw.isEmpty) {
      stderr.writeln('error: missing required --target-version-code <int>');
      return 64;
    }
    final targetVersionCode = int.tryParse(targetVersionCodeRaw);
    if (targetVersionCode == null) {
      stderr.writeln('error: --target-version-code must be an integer');
      return 64;
    }

    try {
      final result = await packPatch(
        apkPath: apk,
        version: version,
        targetVersionCode: targetVersionCode,
        abi: results['abi'] as String?,
        requestedAssets: results['assets'] as List<String>,
        out: results['out'] as String,
      );
      stdout.writeln('[build] version: ${result.version}');
      stdout.writeln('[build] targetVersionCode: ${result.targetVersionCode}');
      stdout.writeln('[build] abis: ${result.abis.join(', ')}');
      stdout.writeln('[build] bundle md5: ${result.md5}');
      stdout.writeln('[build] overlay assets: ${result.assetCount}');
      stdout.writeln('[build] payload: ${result.payloadPath}');
      stdout.writeln('[build] manifest: ${result.manifestPath}');
      return 0;
    } on PackException catch (e) {
      stderr.writeln('error: ${e.message}');
      return e.exitCode;
    } on Object catch (e) {
      stderr.writeln('error: $e');
      return 1;
    }
  }
}
