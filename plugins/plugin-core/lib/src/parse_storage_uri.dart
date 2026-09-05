/// Parsed components of a storage URI.
class ParsedStorageUri {
  const ParsedStorageUri({
    required this.protocol,
    required this.bucket,
    required this.key,
  });

  final String protocol;
  final String bucket;
  final String key;
}

/// Decode percent-encoded storage object keys.
String decodeStorageObjectKey(String key) {
  try {
    return Uri.decodeComponent(key);
  } catch (_) {
    return key;
  }
}

/// Parse a storage URI and validate the protocol.
///
/// Example: `parseStorageUri("s3://my-bucket/path/to/file.zip", "s3")`
///   → `{ protocol: "s3", bucket: "my-bucket", key: "path/to/file.zip" }`
///
/// Faithful port of hot-updater `parseStorageUri.ts`.
ParsedStorageUri parseStorageUri(String storageUri, String expectedProtocol) {
  final uri = Uri.parse(storageUri);
  final protocol = uri.scheme;

  if (protocol != expectedProtocol) {
    throw FormatException(
      'Invalid storage URI protocol. Expected $expectedProtocol, got $protocol',
    );
  }

  return ParsedStorageUri(
    protocol: protocol,
    bucket: uri.host,
    key: decodeStorageObjectKey(
      uri.path.startsWith('/') ? uri.path.substring(1) : uri.path,
    ),
  );
}
