#!/usr/bin/env node
'use strict';

// Launcher for the flutter_ota_kit CLI.
//
// Resolves a platform+arch-specific prebuilt binary (`flutter-ota-<os>-<arch>`)
// shipped next to this script, falling back to `dart run` of the bundled Dart
// source when no prebuilt exists for the current architecture (e.g. a user on
// arm64 with only an x64 binary present). This keeps the package installable on
// any platform that has the Dart SDK, without us needing to ship every binary.

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function platform() {
  if (process.platform === 'win32') return 'windows';
  if (process.platform === 'darwin') return 'macos';
  return 'linux';
}

function arch() {
  // Only x64/arm64 matter for Dart AOT; everything else falls back to Dart VM.
  return process.arch === 'arm64' ? 'arm64' : 'x64';
}

const platformName = platform();
const archName = arch();
const ext = process.platform === 'win32' ? '.exe' : '';
const binDir = __dirname;
const binName = `flutter-ota-${platformName}-${archName}${ext}`;
const binPath = path.join(binDir, binName);

const sourceEntry = path.join(
  binDir, '..', 'dart-src', 'packages', 'cli-tools', 'bin', 'flutter_ota_kit.dart',
);
const cliDir = path.dirname(path.dirname(sourceEntry));

function chmodIfNeeded(p) {
  try {
    const st = fs.statSync(p);
    // Ensure owner-executable bit is set.
    if (!(st.mode & 0o100)) fs.chmodSync(p, st.mode | 0o755);
  } catch (_) {
    // Non-fatal.
  }
}

function run(bin, args) {
  const res = spawnSync(bin, args, { stdio: 'inherit', windowsHide: false });
  process.exit(res.status == null ? 1 : res.status);
}

if (fs.existsSync(binPath)) {
  chmodIfNeeded(binPath);
  run(binPath, process.argv.slice(2));
} else if (
  spawnSync('dart', ['--version'], { stdio: 'ignore' }).status === 0 &&
  fs.existsSync(sourceEntry)
) {
  // Ensure dependencies are resolved before running from source. We only run
  // `dart pub get` when the package config is missing, so repeated invocations
  // don't re-resolve dependencies on every command.
  const configPath = path.join(cliDir, '.dart_tool', 'package_config.json');
  if (!fs.existsSync(configPath)) {
    const getRes = spawnSync('dart', ['pub', 'get'], { stdio: 'inherit', cwd: cliDir });
    if (getRes.status !== 0) {
      console.error(
        'flutter-ota: `dart pub get` failed. Install dependencies or build ' +
          `a prebuilt manually:\n  cd ${cliDir} && dart compile exe ` +
          `bin/flutter_ota_kit.dart -o ${binPath}`,
      );
      process.exit(1);
    }
  }
  chmodIfNeeded(binPath);
  run('dart', [sourceEntry, ...process.argv.slice(2)]);
} else {
  console.error(
    `flutter-ota: no prebuilt binary for ${platformName}-${archName} and ` +
      'the Dart SDK was not found. Install Dart (https://dart.dev) or use a ' +
      'platform/arch with a shipped prebuilt binary.',
  );
  process.exit(1);
}
