/// Throws [ArgumentError] if the bucket parsed from a storage URI does not
/// match the configured bucket. Shared by every S3-compatible storage profile
/// (R2, AWS S3, …) so the check lives in exactly one place.
void ensureExpectedBucket(String bucket, String bucketName) {
  if (bucket != bucketName) {
    throw ArgumentError(
      'Bucket name mismatch: expected "$bucketName", but found "$bucket".',
    );
  }
}

/// Matches the `update.json` manifest key layout
/// `<channel>/<platform>/<version|fingerprintHash>/update.json`.
/// Shared by the blob-database plugins (AWS S3 + the blob-database factory)
/// so the pattern is defined exactly once.
final RegExp updateJsonKeyRegex =
    RegExp(r'^[^/]+/(?:ios|android)/[^/]+/update\.json$');
