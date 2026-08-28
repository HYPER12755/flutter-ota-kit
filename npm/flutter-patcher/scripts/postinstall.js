#!/usr/bin/env node
'use strict';

// Post-install: ensure a runnable flutter-patcher binary exists next to the
// launcher. If a prebuilt platform binary ships in `bin/`, use it. Otherwise
// build one from source with `dart compile exe` when the Dart SDK is present.

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const platform =
  process.platform === 'win32'
    ? 'windows'
    : process.platform === 'darwin'
    ? 'macos'
    : 'linux';
const ext = process.platform === 'win32' ? '.exe' : '';
const pkgDir = path.join(__dirname, '..');
const binDir = path.join(pkgDir, 'bin');
const target = path.join(binDir, `flutter-patcher-${platform}${ext}`);

if (fs.existsSync(target)) {
  console.log('flutter-patcher: prebuilt binary present, skipping build.');
  process.exit(0);
}

const dartCheck = spawnSync('dart', ['--version'], { stdio: 'ignore' });
if (dartCheck.status !== 0) {
  console.warn(
    'flutter-patcher: Dart SDK not found; skipping build. Provide a prebuilt ' +
      'binary in bin/ or install the Dart SDK (https://dart.dev).',
  );
  process.exit(0);
}

// packages/cli-tools/bin/flutter_patcher.dart relative to the repo root.
const repoRoot = path.join(pkgDir, '..', '..', '..');
const dartEntry = path.join(
  repoRoot,
  'packages',
  'cli-tools',
  'bin',
  'flutter_patcher.dart',
);

console.log('flutter-patcher: building binary with `dart compile exe`...');
const res = spawnSync(
  'dart',
  ['compile', 'exe', dartEntry, '-o', target],
  { stdio: 'inherit' },
);
process.exit(res.status == null ? 1 : res.status);
