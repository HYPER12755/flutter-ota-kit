#!/usr/bin/env node
'use strict';

// Post-install: ensure a runnable flutter-ota binary exists next to the
// launcher for the current platform+arch. If a prebuilt
// `flutter-ota-<os>-<arch>` binary ships in `bin/`, use it. Otherwise, when
// the Dart SDK is present, compile one from the bundled Dart source so the
// package works on architectures we did not prebuild (e.g. arm64).
//
// We explicitly run `dart pub get` first so dependency resolution is reliable
// (a stale/locked tree would otherwise fail to fetch packages). If compilation
// cannot be performed we warn (and exit 0) rather than failing the whole npm
// install — the launcher prints a clear "how to build" message at runtime.

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function platform() {
  if (process.platform === 'win32') return 'windows';
  if (process.platform === 'darwin') return 'macos';
  return 'linux';
}

function arch() {
  return process.arch === 'arm64' ? 'arm64' : 'x64';
}

const platformName = platform();
const archName = arch();
const ext = process.platform === 'win32' ? '.exe' : '';
const pkgDir = path.join(__dirname, '..');
const binDir = path.join(pkgDir, 'bin');
const target = path.join(binDir, `flutter-ota-${platformName}-${archName}${ext}`);
const cliDir = path.join(pkgDir, 'dart-src', 'packages', 'cli-tools');

function chmod(pathname) {
  try {
    const st = fs.statSync(pathname);
    if (!(st.mode & 0o100)) fs.chmodSync(pathname, st.mode | 0o755);
  } catch (_) {
    /* non-fatal */
  }
}

if (fs.existsSync(target)) {
  chmod(target);
  console.log(`flutter-ota: prebuilt binary present (${platformName}-${archName}), skipping build.`);
  process.exit(0);
}

const dartCheck = spawnSync('dart', ['--version'], { stdio: 'ignore' });
if (dartCheck.status !== 0) {
  console.warn(
    `flutter-ota: Dart SDK not found; skipping build. Provide a prebuilt ` +
      `binary (bin/flutter-ota-${platformName}-${archName}${ext}) or install ` +
      'the Dart SDK (https://dart.dev).',
  );
  process.exit(0);
}

if (!fs.existsSync(path.join(cliDir, 'pubspec.yaml'))) {
  console.warn('flutter-ota: bundled Dart source not found; skipping build.');
  process.exit(0);
}

console.log('flutter-ota: resolving Dart dependencies (dart pub get)...');
const getRes = spawnSync('dart', ['pub', 'get'], { stdio: 'inherit', cwd: cliDir });
if (getRes.status !== 0) {
  console.error(
    'flutter-ota: `dart pub get` failed (check your network / Dart version). ' +
      `To build manually:\n  cd ${cliDir} && dart compile exe bin/flutter_ota_kit.dart ` +
      `-o ${target}`,
  );
  process.exit(0);
}

console.log(`flutter-ota: building native binary (${platformName}-${archName})...`);
const res = spawnSync(
  'dart',
  ['compile', 'exe', 'bin/flutter_ota_kit.dart', '-o', target],
  { stdio: 'inherit', cwd: cliDir },
);
if (res.status !== 0) {
  console.error(
    'flutter-ota: build failed. To build manually:\n  cd ' +
      `${cliDir} && dart compile exe bin/flutter_ota_kit.dart -o ${target}`,
  );
  process.exit(0);
}
chmod(target);
console.log(`flutter-ota: built ${target}`);
