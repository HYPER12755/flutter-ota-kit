import 'dart:io';

import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('PocketBase install paths', () {
    test('resolve returns a stable, versioned path', () {
      final a = PocketBaseInstallPaths.resolve(version: '0.22.21');
      final b = PocketBaseInstallPaths.resolve(version: '0.22.21');
      expect(a.installDir.path, b.installDir.path);
      expect(a.installDir.path, endsWith(p.join('pocketbase', '0.22.21')));
      expect(
        a.binaryPath.path,
        anyOf(
          endsWith(p.join('0.22.21', 'pocketbase')),
          endsWith(p.join('0.22.21', 'pocketbase.exe')),
        ),
      );
    });

    test('resolve uses custom root', () {
      final tmp = Directory.systemTemp.createTempSync('fp-pb-paths-');
      final a = PocketBaseInstallPaths.resolve(version: '0.22.21', root: tmp);
      expect(a.installDir.path, tmp.path);
      tmp.deleteSync(recursive: true);
    });
  });

  group('PocketBaseDataBootstrap', () {
    test('copies .pb.js hooks on first run, leaves user edits alone', () async {
      final tmp = Directory.systemTemp.createTempSync('fp-pb-data-');
      final source = Directory(p.join(tmp.path, 'src'))
        ..createSync(recursive: true);
      File(p.join(source.path, 'bundles.pb.js'))
          .writeAsStringSync('// hook v1');
      final dataDir = Directory(p.join(tmp.path, 'data'))..createSync();

      final bootstrap = PocketBaseDataBootstrap(
        dataDir: dataDir,
        hooksSourceDir: source,
      );
      final installed = await bootstrap.install();
      expect(installed, ['bundles.pb.js']);
      final copied = File(p.join(dataDir.path, 'pb_hooks', 'bundles.pb.js'));
      expect(copied.existsSync(), isTrue);
      expect(copied.readAsStringSync(), '// hook v1');

      // User edits the copy; second install must not overwrite.
      copied.writeAsStringSync('// user edit');
      final second = await bootstrap.install();
      expect(second, isEmpty);
      expect(copied.readAsStringSync(), '// user edit');

      tmp.deleteSync(recursive: true);
    });

    test('no-op when source dir does not exist', () async {
      final tmp = Directory.systemTemp.createTempSync('fp-pb-data-');
      final source = Directory(p.join(tmp.path, 'missing'));
      final dataDir = Directory(p.join(tmp.path, 'data'))..createSync();
      final bootstrap = PocketBaseDataBootstrap(
        dataDir: dataDir,
        hooksSourceDir: source,
      );
      final installed = await bootstrap.install();
      expect(installed, isEmpty);
      tmp.deleteSync(recursive: true);
    });
  });
}
