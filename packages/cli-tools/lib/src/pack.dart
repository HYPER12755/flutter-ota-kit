import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const List<String> abiPriority = <String>['arm64-v8a', 'armeabi-v7a', 'x86_64'];
const String flutterAssetsPrefix = 'assets/flutter_assets/';
const String assetManifestPath = '${flutterAssetsPrefix}AssetManifest.bin';

/// Result of a successful [packPatch] run.
class PackResult {
  const PackResult({
    required this.payloadPath,
    required this.manifestPath,
    required this.abis,
    required this.md5,
    required this.version,
    required this.targetVersionCode,
    required this.assetCount,
  });

  final String payloadPath;
  final String manifestPath;
  final List<String> abis;
  final String md5;
  final String version;
  final int targetVersionCode;
  final int assetCount;
}

/// Pack a release APK into a device-compatible OTA patch (`patch.zip`).
///
/// Mirrors the standalone `bin/pack.dart` CLI, but as a library usable by the
/// `flutter_patcher build` command. Includes **every** ABI found in the APK so
/// a single bundle serves all device ABIs (the device SDK picks its ABI).
Future<PackResult> packPatch({
  required String apkPath,
  required String version,
  required int targetVersionCode,
  String? abi,
  List<String> requestedAssets = const [],
  required String out,
}) async {
  final apkFile = File(apkPath);
  if (!apkFile.existsSync()) {
    throw PackException('APK not found: $apkPath');
  }

  final apkBytes = apkFile.readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(apkBytes);

  final libs = _collectLibapps(archive);
  if (libs.isEmpty) {
    throw PackException(
      'libapp.so not found in APK for any of $abiPriority '
      '(or requested --abi $abi).',
    );
  }

  if (abi != null && !libs.any((e) => e.$1 == abi)) {
    throw PackException('requested --abi $abi not present in APK.');
  }

  final outDir = Directory(out);
  outDir.createSync(recursive: true);
  final result = _writePatchPackage(
    outDir: outDir,
    archive: archive,
    libs: libs,
    version: version,
    targetVersionCode: targetVersionCode,
    requestedAssets: requestedAssets,
  );
  return result;
}

PackResult _writePatchPackage({
  required Directory outDir,
  required Archive archive,
  required List<(String, List<int>)> libs,
  required String version,
  required int targetVersionCode,
  required List<String> requestedAssets,
}) {
  final patchFiles = <String, _PatchAssetFile>{};
  final operations = <Map<String, dynamic>>[];
  var baseManifestSize = 0;

  if (requestedAssets.isNotEmpty) {
    final manifestEntry = _findFile(archive, assetManifestPath);
    if (manifestEntry == null) {
      throw PackException(
        'AssetManifest.bin not found in APK: $assetManifestPath',
      );
    }
    final manifestBytes = _archiveFileBytes(manifestEntry);
    baseManifestSize = manifestBytes.length;
    final decoded = _FlutterStandardMessageCodec().decode(manifestBytes);
    if (decoded is! Map) {
      throw PackException('AssetManifest.bin must decode to a map.');
    }
    final assetManifest = Map<String, dynamic>.from(decoded);

    for (final key in requestedAssets) {
      final variantsRaw = assetManifest[key];
      if (variantsRaw is! List) {
        throw PackException(
            'asset key not found in AssetManifest.bin: $key');
      }
      final variants = variantsRaw
          .map((variant) => Map<String, dynamic>.from(variant as Map))
          .toList(growable: false);
      operations.add({
        'op': 'upsert',
        'key': key,
        'variants': variants,
      });
      for (final variant in variants) {
        final assetPath = variant['asset'];
        if (assetPath is! String || assetPath.isEmpty) {
          throw PackException('invalid variant asset for key $key');
        }
        _validateArchiveRelativePath(assetPath, 'asset path');
        final apkPath = '$flutterAssetsPrefix$assetPath';
        final entry = _findFile(archive, apkPath);
        if (entry == null) {
          throw PackException(
            'variant file for $key not found in APK: $apkPath',
          );
        }
        final bytes = _archiveFileBytes(entry);
        patchFiles[assetPath] = _PatchAssetFile(
          path: assetPath,
          bytes: bytes,
          md5Hex: md5.convert(bytes).toString(),
        );
      }
    }
  }

  final libManifest = <String, dynamic>{
    for (final (currentAbi, soBytes) in libs) currentAbi: {
      'path': 'lib/$currentAbi/libapp.so',
      'md5': md5.convert(soBytes).toString(),
    },
  };

  final zipManifest = <String, dynamic>{
    'schemaVersion': 2,
    'version': version,
    'targetVersionCode': targetVersionCode,
    'lib': libManifest,
    if (requestedAssets.isNotEmpty)
      'assets': {
        'mode': 'overlay',
        'manifestPatch': 'manifest_patch.json',
        'prefix': 'assets/',
        'files': patchFiles.values
            .map((file) => {
                  'path': file.path,
                  'md5': file.md5Hex,
                  'size': file.bytes.length,
                })
            .toList(),
      },
  };

  final package = Archive()
    ..addFile(_jsonArchiveFile('manifest.json', zipManifest));
  for (final (currentAbi, soBytes) in libs) {
    package.addFile(
        ArchiveFile('lib/$currentAbi/libapp.so', soBytes.length, soBytes));
  }

  if (requestedAssets.isNotEmpty) {
    final manifestPatch = <String, dynamic>{
      'schemaVersion': 1,
      'manifestFormat': 'bin',
      'baseManifestSize': baseManifestSize,
      'operations': operations,
    };
    package.addFile(_jsonArchiveFile('manifest_patch.json', manifestPatch));
    for (final file in patchFiles.values) {
      package.addFile(
        ArchiveFile('assets/${file.path}', file.bytes.length, file.bytes),
      );
    }
  }

  // archive 3.x returns List<int>?, 4.x returns List<int>; coerce to bytes.
  // ignore: unnecessary_nullable_for_final_variable_declarations, dead_null_aware_expression
  final List<int> packageBytes = ZipEncoder().encode(package) ?? const <int>[];
  final outZip = File('${outDir.path}/patch.zip');
  outZip.writeAsBytesSync(packageBytes);

  final payloadMd5 = md5.convert(packageBytes).toString();
  final outerManifest = <String, dynamic>{
    'schemaVersion': 2,
    'version': version,
    'md5': payloadMd5,
    'targetVersionCode': targetVersionCode,
    'abis': libs.map((e) => e.$1).toList(),
    'payload': 'patch.zip',
  };
  _writeJson(File('${outDir.path}/manifest.json'), outerManifest);

  return PackResult(
    payloadPath: outZip.path,
    manifestPath: '${outDir.path}/manifest.json',
    abis: libs.map((e) => e.$1).toList(),
    md5: payloadMd5,
    version: version,
    targetVersionCode: targetVersionCode,
    assetCount: patchFiles.length,
  );
}

ArchiveFile _jsonArchiveFile(String name, Map<String, dynamic> json) {
  final bytes =
      utf8.encode('${const JsonEncoder.withIndent('  ').convert(json)}\n');
  return ArchiveFile(name, bytes.length, bytes);
}

/// Collect every `lib/<abi>/libapp.so` present in the APK.
List<(String, List<int>)> _collectLibapps(Archive archive) {
  final found = <(String, List<int>)>[];
  final seen = <String>{};
  final regex = RegExp(r'^lib/([^/]+)/libapp\.so$');
  for (final file in archive.files) {
    final m = regex.firstMatch(file.name);
    if (m != null && seen.add(m.group(1)!)) {
      found.add((m.group(1)!, _archiveFileBytes(file)));
    }
  }
  found.sort((a, b) {
    final ia = abiPriority.indexOf(a.$1);
    final ib = abiPriority.indexOf(b.$1);
    final ra = ia < 0 ? _nonPriorityRank(a.$1) : ia;
    final rb = ib < 0 ? _nonPriorityRank(b.$1) : ib;
    return ra.compareTo(rb);
  });
  return found;
}

int _nonPriorityRank(String abi) => abiPriority.length;

ArchiveFile? _findFile(Archive archive, String name) {
  for (final file in archive.files) {
    if (!file.isFile) continue;
    if (file.name == name) return file;
  }
  return null;
}

void _writeJson(File file, Map<String, dynamic> json) {
  file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(json)}\n');
}

void _validateArchiveRelativePath(String path, String label) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.startsWith('\\') ||
      path.contains('\u0000') ||
      path.split('/').contains('..')) {
    throw PackException('invalid $label: $path');
  }
}

List<int> _archiveFileBytes(ArchiveFile file) {
  final dynamic dynamicFile = file;
  try {
    return List<int>.from(dynamicFile.readBytes() as List<int>);
  } on NoSuchMethodError {
    return List<int>.from(dynamicFile.content as List<int>);
  }
}

class _PatchAssetFile {
  const _PatchAssetFile({
    required this.path,
    required this.bytes,
    required this.md5Hex,
  });

  final String path;
  final List<int> bytes;
  final String md5Hex;
}

/// Error carrying a stable CLI exit code.
class PackException implements Exception {
  const PackException(this.message, [this.exitCode = 1]);

  final String message;
  final int exitCode;
}

class _FlutterStandardMessageCodec {
  late ByteData _data;
  late int _offset;

  Object? decode(List<int> bytes) {
    final list = Uint8List.fromList(bytes);
    _data = ByteData.sublistView(list);
    _offset = 0;
    final value = _readValue();
    if (_offset != _data.lengthInBytes) {
      throw PackException('AssetManifest.bin has trailing bytes.');
    }
    return value;
  }

  Object? _readValue() {
    final type = _readUint8();
    switch (type) {
      case 0:
        return null;
      case 1:
        return true;
      case 2:
        return false;
      case 3:
        return _readInt32();
      case 4:
        return _readInt64();
      case 6:
        _alignTo(8);
        return _readFloat64();
      case 7:
        final len = _readSize();
        final bytes = _readBytes(len);
        return utf8.decode(bytes);
      case 12:
        final len = _readSize();
        return List<Object?>.generate(len, (_) => _readValue());
      case 13:
        final len = _readSize();
        final map = <Object?, Object?>{};
        for (var i = 0; i < len; i++) {
          map[_readValue()] = _readValue();
        }
        return map;
      default:
        throw PackException(
          'unsupported StandardMessageCodec type in AssetManifest.bin: $type',
        );
    }
  }

  int _readSize() {
    final first = _readUint8();
    if (first < 254) return first;
    if (first == 254) return _readUint16();
    return _readUint32();
  }

  int _readUint8() {
    _ensure(1);
    return _data.getUint8(_offset++);
  }

  int _readUint16() {
    _ensure(2);
    final value = _data.getUint16(_offset, Endian.little);
    _offset += 2;
    return value;
  }

  int _readUint32() {
    _ensure(4);
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int _readInt32() {
    _ensure(4);
    final value = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int _readInt64() {
    _ensure(8);
    final value = _data.getInt64(_offset, Endian.little);
    _offset += 8;
    return value;
  }

  double _readFloat64() {
    _ensure(8);
    final value = _data.getFloat64(_offset, Endian.little);
    _offset += 8;
    return value;
  }

  Uint8List _readBytes(int length) {
    _ensure(length);
    final start = _offset;
    _offset += length;
    return _data.buffer.asUint8List(start, length);
  }

  void _alignTo(int alignment) {
    final mod = _offset % alignment;
    if (mod != 0) _offset += alignment - mod;
  }

  void _ensure(int length) {
    if (_offset + length > _data.lengthInBytes) {
      throw PackException('truncated AssetManifest.bin');
    }
  }
}