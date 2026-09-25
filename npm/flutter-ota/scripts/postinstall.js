#!/usr/bin/env node
'use strict';

// Post-install: ensure a runnable flutter-ota binary exists next to the
// launcher for the current platform+arch. If a prebuilt
// `flutter-ota-<os>-<arch>` binary ships in `bin/`, use it. Otherwise, when
// the Flutter SDK is present, compile one from the bundled Dart source so the
// package works on architectures we did not prebuild (e.g. arm64).
//
// NOTE (v0.2.0+): the CLI now depends on the merged `flutter_ota_kit` package,
// which is a Flutter plugin. Dependency resolution therefore needs the Flutter
// SDK (`flutter pub get`), not just the Dart SDK. The compiled executable
// itself is still a plain Dart binary (the CLI only touches the pure-Dart
// backend code, not Flutter widgets). If Flutter is unavailable we warn and
// exit 0 rather than failing the whole npm install.

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
const flutterCheck = spawnSync('flutter', ['--version'], { stdio: 'ignore' });
if (dartCheck.status !== 0 || flutterCheck.status !== 0) {
  console.warn(
    `flutter-ota: Flutter SDK not found; skipping build. Provide a prebuilt ` +
      `binary (bin/flutter-ota-${platformName}-${archName}${ext}) or install ` +
      'the Flutter SDK (https://flutter.dev). The CLI depends on the ' +
      '`flutter_ota_kit` Flutter package, so `flutter pub get` is required.',
  );
  process.exit(0);
}

if (!fs.existsSync(path.join(cliDir, 'pubspec.yaml'))) {
  console.warn('flutter-ota: bundled Dart source not found; skipping build.');
  process.exit(0);
}

console.log('flutter-ota: resolving dependencies (flutter pub get)...');
const getRes = spawnSync('flutter', ['pub', 'get'], { stdio: 'inherit', cwd: cliDir });
if (getRes.status !== 0) {
  console.error(
    'flutter-ota: `flutter pub get` failed (check your network / Flutter version). ' +
      `To build manually:\n  cd ${cliDir} && flutter pub get && dart compile exe ` +
      `bin/flutter_ota_kit.dart -o ${target}`,
  );
  process.exit(0);
}

console.log(`flutter-ota: building native binary (${platformName}-${archName})...`);
  // Ensure bin directory exists
  if (!fs.existsSync(binDir)) {
    fs.mkdirSync(binDir, { recursive: true });
  }
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
