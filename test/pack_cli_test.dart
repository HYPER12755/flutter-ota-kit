import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bin/pack.dart' as pack;

void main() {
  test('pack emits Dart-only patch.zip when no --assets is passed', () async {
    final temp = await Directory.systemTemp.createTemp('flutter_ota_kit_pack_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final apk = File('${temp.path}/app-release.apk');
    final soBytes = utf8.encode('fake libapp.so bytes');
    final archive = Archive()
      ..addFile(
          ArchiveFile('lib/arm64-v8a/libapp.so', soBytes.length, soBytes));
    await apk.writeAsBytes(ZipEncoder().encode(archive));

    final outDir = Directory('${temp.path}/dist');
    final exitCode = await pack.main([
      '--apk',
      apk.path,
      '--version',
      '1.0.0-h1',
      '--target-version-code',
      '100',
      '--out',
      outDir.path,
    ]);

    expect(exitCode, 0);
    expect(File('${outDir.path}/libapp.so').existsSync(), isFalse,
        reason: 'pack should no longer emit bare libapp.so');

    final patchZipBytes = await File('${outDir.path}/patch.zip').readAsBytes();
    final outerManifest = jsonDecode(
      await File('${outDir.path}/manifest.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(outerManifest['version'], '1.0.0-h1');
    expect(outerManifest['schemaVersion'], 2);
    expect(outerManifest['payload'], 'patch.zip');
    expect(outerManifest['targetVersionCode'], 100);
    expect(outerManifest['abis'], <String>['arm64-v8a']);
    expect(outerManifest['md5'], md5.convert(patchZipBytes).toString());

    final patchZip = ZipDecoder().decodeBytes(patchZipBytes);
    final entryNames = patchZip.files.map((f) => f.name).toSet();
    expect(
        entryNames,
        containsAll(<String>{
          'manifest.json',
          'lib/arm64-v8a/libapp.so',
        }));
    expect(entryNames.contains('manifest_patch.json'), isFalse,
        reason: 'Dart-only patch.zip should not embed manifest_patch.json');
    expect(entryNames.any((n) => n.startsWith('assets/')), isFalse,
        reason: 'Dart-only patch.zip should not embed overlay assets');
    expect(_entryBytes(patchZip, 'lib/arm64-v8a/libapp.so'), soBytes);

    final innerManifest = jsonDecode(utf8.decode(
      _entryBytes(patchZip, 'manifest.json'),
    )) as Map<String, dynamic>;
    expect(innerManifest['schemaVersion'], 2);
    expect(innerManifest.containsKey('assets'), isFalse,
        reason: 'Dart-only inner manifest should omit the assets block');
    final lib = innerManifest['lib'] as Map<String, dynamic>;
    final libEntry = lib['arm64-v8a'] as Map<String, dynamic>;
    expect(libEntry['path'], 'lib/arm64-v8a/libapp.so');
    expect(libEntry['md5'], md5.convert(soBytes).toString());
  });

  test('pack writes patch.zip with selected asset variants', () async {
    final temp = await Directory.systemTemp.createTemp('flutter_ota_kit_pack_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final assetManifest = <String, Object?>{
      'images/hero.png': [
        {'asset': 'images/hero.png'},
        {'asset': 'images/2.0x/hero.png', 'dpr': 2.0},
      ],
      'config/app.json': [
        {'asset': 'config/app.json'},
      ],
    };
    final encodedManifest =
        StandardMessageCodec().encodeMessage(assetManifest)!;
    final manifestBytes = encodedManifest.buffer.asUint8List(
      encodedManifest.offsetInBytes,
      encodedManifest.lengthInBytes,
    );
    final soBytes = utf8.encode('fake libapp.so bytes');
    final heroBytes = utf8.encode('hero 1x');
    final hero2Bytes = utf8.encode('hero 2x');

    final archive = Archive()
      ..addFile(ArchiveFile('lib/arm64-v8a/libapp.so', soBytes.length, soBytes))
      ..addFile(ArchiveFile(
        'assets/flutter_assets/AssetManifest.bin',
        manifestBytes.length,
        manifestBytes,
      ))
      ..addFile(ArchiveFile(
        'assets/flutter_assets/images/hero.png',
        heroBytes.length,
        heroBytes,
      ))
      ..addFile(ArchiveFile(
        'assets/flutter_assets/images/2.0x/hero.png',
        hero2Bytes.length,
        hero2Bytes,
      ));
    final apk = File('${temp.path}/app-release.apk');
    await apk.writeAsBytes(ZipEncoder().encode(archive));

    final outDir = Directory('${temp.path}/dist');
    final exitCode = await pack.main([
      '--apk',
      apk.path,
      '--version',
      '1.0.0-h1',
      '--target-version-code',
      '100',
      '--assets',
      'images/hero.png',
      '--assets',
      'images/hero.png',
      '--out',
      outDir.path,
    ]);

    expect(exitCode, 0);
    final outerManifest = jsonDecode(
      await File('${outDir.path}/manifest.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(outerManifest['payload'], 'patch.zip');
    expect(
        outerManifest['md5'],
        md5
            .convert(
              await File('${outDir.path}/patch.zip').readAsBytes(),
            )
            .toString());

    final patchZip = ZipDecoder().decodeBytes(
      await File('${outDir.path}/patch.zip').readAsBytes(),
    );
    expect(_entryBytes(patchZip, 'lib/arm64-v8a/libapp.so'), soBytes);
    expect(_entryBytes(patchZip, 'assets/images/hero.png'), heroBytes);
    expect(_entryBytes(patchZip, 'assets/images/2.0x/hero.png'), hero2Bytes);

    final packageManifest = jsonDecode(utf8.decode(
      _entryBytes(patchZip, 'manifest.json'),
    )) as Map<String, dynamic>;
    expect(packageManifest['schemaVersion'], 2);
    expect((packageManifest['assets'] as Map)['mode'], 'overlay');

    final manifestPatch = jsonDecode(utf8.decode(
      _entryBytes(patchZip, 'manifest_patch.json'),
    )) as Map<String, dynamic>;
    expect(manifestPatch['schemaVersion'], 1);
    final operations = manifestPatch['operations'] as List<dynamic>;
    expect(operations, hasLength(1));
    expect((operations.single as Map)['op'], 'upsert');
    expect((operations.single as Map)['key'], 'images/hero.png');
  });

  test('pack rejects selected asset missing from manifest', () async {
    final temp = await Directory.systemTemp.createTemp('flutter_ota_kit_pack_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final encodedManifest = StandardMessageCodec().encodeMessage(
      <String, Object?>{},
    )!;
    final manifestBytes = encodedManifest.buffer.asUint8List(
      encodedManifest.offsetInBytes,
      encodedManifest.lengthInBytes,
    );
    final soBytes = utf8.encode('fake libapp.so bytes');
    final archive = Archive()
      ..addFile(ArchiveFile('lib/arm64-v8a/libapp.so', soBytes.length, soBytes))
      ..addFile(ArchiveFile(
        'assets/flutter_assets/AssetManifest.bin',
        manifestBytes.length,
        manifestBytes,
      ));
    final apk = File('${temp.path}/app-release.apk');
    await apk.writeAsBytes(ZipEncoder().encode(archive));

    final exitCode = await pack.main([
      '--apk',
      apk.path,
      '--version',
      '1.0.0-h1',
      '--target-version-code',
      '100',
      '--assets',
      'images/missing.png',
      '--out',
      '${temp.path}/dist',
    ]);

    expect(exitCode, 1);
  });

  test('pack reads asset keys from @file with comments and mixed inline',
      () async {
    final temp = await Directory.systemTemp.createTemp('flutter_ota_kit_pack_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final assetManifest = <String, Object?>{
      'images/hero.png': [
        {'asset': 'images/hero.png'},
      ],
      'config/app.json': [
        {'asset': 'config/app.json'},
      ],
      'strings/zh.json': [
        {'asset': 'strings/zh.json'},
      ],
    };
    final encodedManifest =
        StandardMessageCodec().encodeMessage(assetManifest)!;
    final manifestBytes = encodedManifest.buffer.asUint8List(
      encodedManifest.offsetInBytes,
      encodedManifest.lengthInBytes,
    );
    final soBytes = utf8.encode('fake libapp.so bytes');

    final archive = Archive()
      ..addFile(ArchiveFile('lib/arm64-v8a/libapp.so', soBytes.length, soBytes))
      ..addFile(ArchiveFile(
        'assets/flutter_assets/AssetManifest.bin',
        manifestBytes.length,
        manifestBytes,
      ))
      ..addFile(ArchiveFile(
        'assets/flutter_assets/images/hero.png',
        4,
        utf8.encode('hero'),
      ))
      ..addFile(ArchiveFile(
        'assets/flutter_assets/config/app.json',
        4,
        utf8.encode('cfg!'),
      ))
      ..addFile(ArchiveFile(
        'assets/flutter_assets/strings/zh.json',
        4,
        utf8.encode('zh!!'),
      ));
    final apk = File('${temp.path}/app-release.apk');
    await apk.writeAsBytes(ZipEncoder().encode(archive));

    final listFile = File('${temp.path}/patch-assets.txt');
    await listFile.writeAsString(
      [
        '# core patch',
        'images/hero.png',
        '',
        '   config/app.json   ',
        '# extras handled below',
      ].join('\r\n'),
    );

    final outDir = Directory('${temp.path}/dist');
    final exitCode = await pack.main([
      '--apk',
      apk.path,
      '--version',
      '1.0.0-h1',
      '--target-version-code',
      '100',
      '--assets',
      '@${listFile.path},strings/zh.json',
      '--out',
      outDir.path,
    ]);

    expect(exitCode, 0);

    final patchZip = ZipDecoder().decodeBytes(
      await File('${outDir.path}/patch.zip').readAsBytes(),
    );
    final manifestPatch = jsonDecode(utf8.decode(
      _entryBytes(patchZip, 'manifest_patch.json'),
    )) as Map<String, dynamic>;
    final operations = manifestPatch['operations'] as List<dynamic>;
    expect(operations.map((op) => (op as Map)['key']).toList(), <String>[
      'images/hero.png',
      'config/app.json',
      'strings/zh.json',
    ]);
  });

  test('pack rejects @file path that does not exist', () async {
    final temp = await Directory.systemTemp.createTemp('flutter_ota_kit_pack_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final soBytes = utf8.encode('fake libapp.so bytes');
    final archive = Archive()
      ..addFile(
          ArchiveFile('lib/arm64-v8a/libapp.so', soBytes.length, soBytes));
    final apk = File('${temp.path}/app-release.apk');
    await apk.writeAsBytes(ZipEncoder().encode(archive));

    final exitCode = await pack.main([
      '--apk',
      apk.path,
      '--version',
      '1.0.0-h1',
      '--target-version-code',
      '100',
      '--assets',
      '@${temp.path}/does-not-exist.txt',
      '--out',
      '${temp.path}/dist',
    ]);

    expect(exitCode, 66);
  });

  test('pack rejects nested @-include inside an asset list file', () async {
    final temp = await Directory.systemTemp.createTemp('flutter_ota_kit_pack_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final soBytes = utf8.encode('fake libapp.so bytes');
    final archive = Archive()
      ..addFile(
          ArchiveFile('lib/arm64-v8a/libapp.so', soBytes.length, soBytes));
    final apk = File('${temp.path}/app-release.apk');
    await apk.writeAsBytes(ZipEncoder().encode(archive));

    final listFile = File('${temp.path}/list.txt');
    await listFile.writeAsString('@nested.txt\n');

    final exitCode = await pack.main([
      '--apk',
      apk.path,
      '--version',
      '1.0.0-h1',
      '--target-version-code',
      '100',
      '--assets',
      '@${listFile.path}',
      '--out',
      '${temp.path}/dist',
    ]);

    expect(exitCode, 65);
  });
}

List<int> _entryBytes(Archive archive, String name) {
  final entry = archive.files.singleWhere((file) => file.name == name);
  final dynamic dynamicEntry = entry;
  try {
    return List<int>.from(dynamicEntry.readBytes() as List<int>);
  } on NoSuchMethodError {
    return List<int>.from(dynamicEntry.content as List<int>);
  }
}
