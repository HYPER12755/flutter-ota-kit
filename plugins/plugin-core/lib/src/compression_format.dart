import 'package:mime/mime.dart' as mime_pkg;

/// Supported compression formats for bundle deployment.
enum CompressionFormat { zip, tarBr, tarGz }

class CompressionFormatInfo {
  const CompressionFormatInfo({
    required this.format,
    required this.fileExtension,
    this.mimeType,
  });

  final CompressionFormat format;
  final String fileExtension;
  final String? mimeType;
}

const Map<CompressionFormat, CompressionFormatInfo> compressionFormats = {
  CompressionFormat.zip: CompressionFormatInfo(
    format: CompressionFormat.zip,
    fileExtension: '.zip',
    mimeType: 'application/zip',
  ),
  CompressionFormat.tarBr: CompressionFormatInfo(
    format: CompressionFormat.tarBr,
    fileExtension: '.tar.br',
    mimeType: 'application/x-tar',
  ),
  CompressionFormat.tarGz: CompressionFormatInfo(
    format: CompressionFormat.tarGz,
    fileExtension: '.tar.gz',
    mimeType: 'application/x-tar',
  ),
};

/// Detect compression format from filename.
CompressionFormatInfo detectCompressionFormat(String filename) {
  for (final info in compressionFormats.values) {
    if (filename.endsWith(info.fileExtension)) {
      return info;
    }
  }
  return compressionFormats[CompressionFormat.zip]!;
}

/// Get MIME type for a filename.
String? getCompressionMimeType(String filename) {
  return detectCompressionFormat(filename).mimeType;
}

/// Get Content-Type for a bundle file with 3-tier fallback.
///
/// Faithful port of hot-updater `compressionFormat.ts`.
String getContentType(String bundlePath) {
  final filename = bundlePath
      .replaceAll(RegExp(r'[\\/]+$'), '')
      .split(RegExp(r'[\\/]'))
      .last;

  return mime_pkg.lookupMimeType(bundlePath) ??
      getCompressionMimeType(filename) ??
      'application/octet-stream';
}
