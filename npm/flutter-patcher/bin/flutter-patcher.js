#!/usr/bin/env node
'use strict';

// Launcher for the flutter_patcher CLI.
//
// Resolves the prebuilt Dart binary shipped next to this script (platform
// specific), falling back to `dart run` when Dart is available and no binary
// is present. This lets `npm i -g flutter-patcher` work on any machine that
// either ships a prebuilt binary or has the Dart SDK installed.

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
const binDir = __dirname;
const binName = `flutter-patcher-${platform}${ext}`;
const binPath = path.join(binDir, binName);

function run(bin, args) {
  const res = spawnSync(bin, args, { stdio: 'inherit', windowsHide: false });
  process.exit(res.status == null ? 1 : res.status);
}

if (fs.existsSync(binPath)) {
  run(binPath, process.argv.slice(2));
  return;
}

// Fallback: run from source via the Dart SDK (works when this npm package is
// installed from the monorepo, since the Dart package lives at
// ../../packages/cli-tools/bin/flutter_patcher.dart).
const repoEntry = path.join(
  binDir,
  '..',
  '..',
  '..',
  'packages',
  'cli-tools',
  'bin',
  'flutter-patcher.dart',
);
const dartCheck = spawnSync('dart', ['--version'], { stdio: 'ignore' });
if (dartCheck.status === 0 && fs.existsSync(repoEntry)) {
  run('dart', [repoEntry, ...process.argv.slice(2)]);
  return;
}

console.error(
  'flutter-patcher: no prebuilt binary for this platform and Dart SDK not ' +
    'found. Install Dart (https://dart.dev) or ship a prebuilt binary.',
);
process.exit(1);
