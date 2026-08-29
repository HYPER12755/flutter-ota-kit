import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_ota_kit/src/pack/pack.dart';

Future<int> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption(
      'apk',
      abbr: 'a',
      help: 'Path to the release APK to extract libapp.so and assets from.',
    )
    ..addMultiOption(
      'assets',
      help: 'Flutter asset key(s) from pubspec.yaml to include in patch.zip. '
          'Can be repeated or comma-separated. '
          'Use --assets @path/to/list.txt to read keys from a UTF-8 file '
          '(one per line, # starts comments). Inline keys and @file can be mixed: '
          '--assets @list.txt,assets/extra.png',
    )
    ..addOption(
      'version',
      help: 'Patch version string (goes into manifest.version).',
    )
    ..addOption(
      'target-version-code',
      help: 'Host APK versionCode the patch is built for (integer).',
    )
    ..addOption(
      'abi',
      help: 'Preferred ABI to report. Default: all ABIs found in APK.',
    )
    ..addOption(
      'out',
      abbr: 'o',
      help: 'Output directory. Created if absent.',
      defaultsTo: 'dist',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help.');

  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}');
    stderr.writeln(parser.usage);
    return 64;
  }

  if (args['help'] as bool) {
    stdout.writeln('flutter_ota_kit pack CLI\n');
    stdout.writeln('usage: dart run bin/pack.dart [options]\n');
    stdout.writeln(parser.usage);
    return 0;
  }

  final apkPath = args['apk'] as String?;
  final version = args['version'] as String?;
  final vcRaw = args['target-version-code'] as String?;
  if (apkPath == null || version == null || vcRaw == null) {
    stderr.writeln(
      'error: --apk, --version, --target-version-code are required.',
    );
    stderr.writeln(parser.usage);
    return 64;
  }

  final targetVersionCode = int.tryParse(vcRaw);
  if (targetVersionCode == null) {
    stderr.writeln('error: --target-version-code must be an integer.');
    return 64;
  }

  final List<String> requestedAssets;
  try {
    requestedAssets = _readRequestedAssets(
      assetsArgs: args['assets'] as List<String>,
    );
  } on PackException catch (e) {
    stderr.writeln('error: ${e.message}');
    return e.exitCode;
  }

  final apkFile = File(apkPath);
  if (!apkFile.existsSync()) {
    stderr.writeln('error: APK not found: $apkPath');
    return 66;
  }

  stdout.writeln('[pack] reading ${apkFile.path}');
  try {
    final result = await packPatch(
      apkPath: apkPath,
      version: version,
      targetVersionCode: targetVersionCode,
      abi: args['abi'] as String?,
      requestedAssets: requestedAssets,
      out: args['out'] as String,
    );
    if (requestedAssets.isNotEmpty) {
      stdout.writeln('[pack] assets: ${requestedAssets.length} key(s)');
      stdout.writeln('[pack] overlay files: ${result.assetCount}');
    }
    stdout.writeln('[pack] abis: ${result.abis.join(', ')}');
    stdout.writeln('[pack] payload: ${result.payloadPath}');
    stdout.writeln('[pack] md5: ${result.md5}');
    stdout.writeln('[pack] manifest: ${result.manifestPath}');
    return 0;
  } on PackException catch (e) {
    stderr.writeln('error: ${e.message}');
    return e.exitCode;
  }
}

List<String> _readRequestedAssets({
  Iterable<String> assetsArgs = const [],
}) {
  final result = <String>[];
  final seen = <String>{};

  void appendKey(String raw, {required String source}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return;
    if (trimmed.startsWith('@')) {
      throw PackException(
        'nested @-includes are not supported inside $source. '
        'List asset keys directly, one per line.',
        65,
      );
    }
    final normalized = trimmed.replaceAll('\\', '/');
    _validateArchiveRelativePath(normalized, 'asset key');
    if (seen.add(normalized)) result.add(normalized);
  }

  for (final assetsArg in assetsArgs) {
    if (assetsArg.trim().isEmpty) continue;
    for (final token in assetsArg.split(',')) {
      final trimmed = token.trim();
      if (trimmed.isEmpty) continue;
      if (!trimmed.startsWith('@')) {
        appendKey(trimmed, source: '--assets');
        continue;
      }
      final filePath = trimmed.substring(1);
      if (filePath.isEmpty) {
        throw PackException(
          'invalid --assets value: "@" must be followed by a file path.',
          64,
        );
      }
      final file = File(filePath);
      if (!file.existsSync()) {
        throw PackException('asset list file not found: $filePath', 66);
      }
      final List<String> lines;
      try {
        lines = file.readAsLinesSync();
      } on FileSystemException catch (e) {
        throw PackException(
          'failed to read asset list as UTF-8 text: $filePath. '
          'For a single binary asset, drop the "@" and pass the path directly. '
          '(${e.message})',
          65,
        );
      }
      for (final line in lines) {
        appendKey(line, source: filePath);
      }
    }
  }
  return result;
}

void _validateArchiveRelativePath(String path, String label) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.startsWith('\\') ||
      path.contains('\u0000') ||
      path.split('/').contains('..')) {
    throw PackException('invalid $label: $path', 65);
  }
}
