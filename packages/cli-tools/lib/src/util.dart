import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Hex-encoded SHA-256 of [bytes].
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Zip [directory] into a temp file and return its path.
///
/// File paths inside the archive are relative to [directory], matching
/// hot-updater's bundle layout.
Future<String> zipDirectory(String directory) async {
  final dir = Directory(directory);
  if (!dir.existsSync()) {
    throw StateError('Source directory does not exist: $directory');
  }
  final archive = Archive();
  await for (final entity in dir.list(recursive: true)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: dir.path);
    final bytes = await entity.readAsBytes();
    archive.addFile(ArchiveFile(relative, bytes.length, bytes));
  }
  if (archive.files.isEmpty) {
    throw StateError('Source directory is empty: $directory');
  }
  final encoder = ZipEncoder();
  final out = encoder.encode(archive);
  final tmp = File('${Directory.systemTemp.path}/fp_${Random().nextInt(1 << 30)}.zip');
  await tmp.writeAsBytes(out);
  return tmp.path;
}

/// Compute a deterministic fingerprint hash for a directory (used at build time
/// to stamp the app's runtime fingerprint).
///
/// The hash covers every file's relative path + content hash, sorted for
/// stability, so identical trees always yield the same fingerprint.
String generateFingerprint(String directory) {
  final dir = Directory(directory);
  if (!dir.existsSync()) {
    throw StateError('Directory does not exist: $directory');
  }
  final entries = <String>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: dir.path);
    final content = File(entity.path).readAsBytesSync();
    final hash = sha256Hex(content);
    entries.add('$relative:$hash');
  }
  entries.sort();
  return sha256Hex(utf8.encode(entries.join('\n')));
}

/// Best-effort git commit hash for a directory.
Future<String?> gitCommitHash(String directory) async {
  try {
    final result = await Process.run(
      'git',
      ['rev-parse', 'HEAD'],
      workingDirectory: directory,
      runInShell: true,
    );
    if (result.exitCode == 0) {
      return (result.stdout as String).trim();
    }
  } catch (_) {
    // git unavailable — ignore.
  }
  return null;
}

/// Human readable byte size.
String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}
