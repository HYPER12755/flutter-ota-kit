import 'dart:convert' show jsonDecode;

/// Normalize bundle `metadata` from various shapes (a JSON string or an
/// already-decoded object) to a plain map. Identical across every backend
/// mapper (supabase / postgres / cloudflare), so it lives here once.
Map<String, Object?>? normalizeMetadata(Object? value) {
  if (value == null) return null;
  if (value is String) {
    try {
      final parsed = jsonDecode(value);
      return normalizeMetadata(parsed);
    } catch (_) {
      return null;
    }
  }
  if (value is Map) return value.cast<String, Object?>();
  return null;
}

/// Compound primary key for a patch row: `${bundleId}:${baseBundleId}`.
/// Shared by every backend mapper.
String buildBundlePatchId(String bundleId, String baseBundleId) =>
    '$bundleId:$baseBundleId';
