/// Parsed components of a storage URI.
///
/// Storage URIs follow a protocol-specific scheme that maps to a backend
/// storage service. Supported protocols:
///
/// - `s3://bucket/key` — AWS S3
/// - `r2://bucket/key` — Cloudflare R2
/// - `supabase-storage://bucket/key` — Supabase Storage
/// - `postgres://host/db` — Postgres (via HTTP API)
/// - `pocketbase://host/api/files/bucket/key` — PocketBase
///
/// The [bucket] is the storage container, and [key] is the object path
/// within that container.
class ParsedStorageUri {
  const ParsedStorageUri({
    required this.protocol,
    required this.bucket,
    required this.key,
  });

  /// Protocol scheme (e.g. `s3`, `r2`, `supabase-storage`).
  final String protocol;

  /// Storage container / bucket name.
  final String bucket;

  /// Object path within the bucket (percent-decoded).
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
