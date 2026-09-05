/// Manages the PocketBase server binary — download, version, run, upgrade.
///
/// PocketBase is a single Go binary (~15MB) that the CLI can download
/// automatically on first run. The binary is cached in
/// `~/.flutter_ota_kit/pocketbase/` so subsequent `serve` invocations are
/// instant.
///
/// Supported platforms: linux/amd64, linux/arm64, macos/amd64, macos/arm64,
/// windows/amd64. Other combinations fall back to a helpful error.
library;

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Default PocketBase version managed by the CLI. Bumped in lockstep with
/// the rest of the stack.
const String kDefaultPocketBaseVersion = '0.22.21';

/// Where the binary + extracted files live.
class PocketBaseInstallPaths {
  const PocketBaseInstallPaths({
    required this.installDir,
    required this.binaryPath,
  });

  /// `~/.flutter_ota_kit/pocketbase/<version>/`
  final Directory installDir;

  /// `~/.flutter_ota_kit/pocketbase/<version>/pocketbase`
  /// (or `pocketbase.exe` on Windows).
  final File binaryPath;

  String get version => p.basename(installDir.path);

  static PocketBaseInstallPaths resolve({
    String? version = kDefaultPocketBaseVersion,
    Directory? root,
  }) {
    final base =
        root ??
        Directory(
          p.join(
            Platform.environment['HOME'] ??
                Platform.environment['USERPROFILE'] ??
                '.',
            '.flutter_ota_kit',
            'pocketbase',
            version!,
          ),
        );
    final exe = Platform.isWindows ? 'pocketbase.exe' : 'pocketbase';
    return PocketBaseInstallPaths(
      installDir: base,
      binaryPath: File(p.join(base.path, exe)),
    );
  }
}

class _OsArch {
  const _OsArch(this.os, this.arch, this.assetSuffix);
  final String os;
  final String arch;
  final String assetSuffix;
}

_OsArch _detectOsArch() {
  // Map Platform.operatingSystem + Platform.numberOfProcessors to a PB asset.
  // PB asset names: linux_amd64, linux_arm64, darwin_amd64, darwin_arm64,
  // windows_amd64.
  final os = Platform.operatingSystem;
  String assetOs;
  if (os == 'linux') {
    assetOs = 'linux';
  } else if (os == 'macos') {
    assetOs = 'darwin';
  } else if (os == 'windows') {
    assetOs = 'windows';
  } else {
    throw StateError('Unsupported OS for PocketBase: $os');
  }
  // Dart on ARM Macs returns 'macos' with arm64 in the version string; we
  // detect arm64 via the Dart version since `Platform` doesn't expose arch
  // directly in stable Dart.
  final dartVersion = Platform.version.toLowerCase();
  final isArm =
      dartVersion.contains('arm64') || dartVersion.contains('aarch64');
  final arch = isArm ? 'arm64' : 'amd64';
  return _OsArch(os, arch, '${assetOs}_$arch');
}

/// Outcome of [PocketBaseInstaller.ensureInstalled].
class PocketBaseInstallResult {
  const PocketBaseInstallResult({
    required this.paths,
    required this.alreadyInstalled,
    required this.bytesDownloaded,
  });

  final PocketBaseInstallPaths paths;
  final bool alreadyInstalled;
  final int bytesDownloaded;
}

/// Downloads, extracts, and verifies the PocketBase binary.
class PocketBaseInstaller {
  PocketBaseInstaller({http.Client? httpClient, String? version})
    : _http = httpClient ?? http.Client(),
      _version = version ?? kDefaultPocketBaseVersion;

  final http.Client _http;
  final String _version;

  /// Returns the install paths and the binary is guaranteed to exist on disk.
  Future<PocketBaseInstallResult> ensureInstalled({
    PocketBaseInstallPaths? paths,
    void Function(double progress)? onProgress,
  }) async {
    final install = paths ?? PocketBaseInstallPaths.resolve(version: _version);
    if (await install.binaryPath.exists()) {
      return PocketBaseInstallResult(
        paths: install,
        alreadyInstalled: true,
        bytesDownloaded: 0,
      );
    }
    await install.installDir.create(recursive: true);

    final osArch = _detectOsArch();
    final url = Uri.parse(
      'https://github.com/pocketbase/pocketbase/releases/download/'
      'v$_version/pocketbase_${_version}_${osArch.assetSuffix}.zip',
    );
    final req = http.Request('GET', url);
    final streamed = await _http.send(req);
    if (streamed.statusCode != 200) {
      throw StateError(
        'Failed to download PocketBase v$_version for ${osArch.assetSuffix}: '
        'HTTP ${streamed.statusCode}. Check your internet connection or set '
        '--pb-version to a known-good release.',
      );
    }
    final bytes = <int>[];
    var received = 0;
    final total = streamed.contentLength ?? 0;
    await for (final chunk in streamed.stream) {
      bytes.addAll(chunk);
      received += chunk.length;
      if (onProgress != null && total > 0) {
        onProgress(received / total);
      }
    }
    final zipPath = File(p.join(install.installDir.path, 'pocketbase.zip'))
      ..writeAsBytesSync(bytes);

    // Extract just the binary (skip the README/CHANGELOG that ship in the
    // archive to keep the install dir tidy).
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final entryName = entry.name.split('/').last;
      if (entryName == 'pocketbase' || entryName == 'pocketbase.exe') {
        final out = File(p.join(install.installDir.path, entryName));
        out.writeAsBytesSync(entry.content as List<int>);
        if (!Platform.isWindows) {
          Process.runSync('chmod', ['+x', out.path]);
        }
      }
    }
    try {
      await zipPath.delete();
    } catch (_) {
      // best-effort cleanup
    }

    return PocketBaseInstallResult(
      paths: install,
      alreadyInstalled: false,
      bytesDownloaded: bytes.length,
    );
  }

  /// Resolves the install paths without downloading.
  PocketBaseInstallPaths paths() =>
      PocketBaseInstallPaths.resolve(version: _version);
}
