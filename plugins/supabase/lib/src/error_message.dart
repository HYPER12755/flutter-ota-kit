/// Shared error-to-message helper used across the supabase plugin
/// (storage, signed-url batcher, edge-function storage). Identical copies used
/// to live in three files; they now all call this one.
String errorMessage(Object? error) {
  if (error is Error) return error.toString();
  if (error is Exception) return error.toString();
  if (error is Map && error['message'] is String) {
    return error['message'] as String;
  }
  return error.toString();
}
