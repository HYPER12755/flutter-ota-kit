/// Bootstraps a fresh PocketBase data directory with the flutter_ota_kit
/// schema defaults (hooks, settings) the first time PB is started.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies the bundled hooks into `pb_data/pb_hooks/` so PB picks them up on
/// the next `serve`. Existing files are left alone so user edits are kept.
class PocketBaseDataBootstrap {
  const PocketBaseDataBootstrap({
    required this.dataDir,
    required this.hooksSourceDir,
  });

  final Directory dataDir;
  final Directory hooksSourceDir;

  Future<List<String>> install() async {
    await dataDir.create(recursive: true);
    final hooksDir = Directory(p.join(dataDir.path, 'pb_hooks'));
    await hooksDir.create(recursive: true);
    final installed = <String>[];
    if (!hooksSourceDir.existsSync()) {
      return installed;
    }
    for (final entry in hooksSourceDir.listSync()) {
      if (entry is! File) continue;
      if (!entry.path.endsWith('.pb.js')) continue;
      final out = File(p.join(hooksDir.path, p.basename(entry.path)));
      if (!await out.exists()) {
        await entry.copy(out.path);
        installed.add(p.basename(entry.path));
      }
    }
    return installed;
  }
}
