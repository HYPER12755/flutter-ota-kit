/// Abstraction over the Supabase client used by the database + storage plugins.
///
/// Mirrors the TS `vi.mock("@supabase/supabase-js")` test seam: in production
/// this wraps the real `supabase` Dart package; in tests a mock implementation
/// is supplied via the plugin config's `clientFactory`.
library;

/// Minimal PostgREST query-builder surface used by the database plugin.
abstract class SupabaseQueryBuilderLike {
  SupabaseFilterBuilderLike select(String columns, {bool? count, bool? head});

  SupabaseFilterBuilderLike delete();

  Future<dynamic> upsert(dynamic values, {String? onConflict});
}

/// Minimal PostgREST filter-builder surface.
abstract class SupabaseFilterBuilderLike {
  SupabaseFilterBuilderLike eq(String column, Object? value);
  SupabaseFilterBuilderLike gt(String column, Object? value);
  SupabaseFilterBuilderLike gte(String column, Object? value);
  SupabaseFilterBuilderLike lt(String column, Object? value);
  SupabaseFilterBuilderLike lte(String column, Object? value);
  SupabaseFilterBuilderLike in_(String column, List<Object?> values);
  SupabaseFilterBuilderLike isFilter(String column, Object? value);
  SupabaseFilterBuilderLike not(String column, String operator, Object? value);
  SupabaseFilterBuilderLike order(String column, {bool? ascending});
  SupabaseFilterBuilderLike limit(int value);
  SupabaseFilterBuilderLike range(int from, int to);
  SupabaseFilterBuilderLike single();
  Future<SupabaseResponseLike> execute();
}

/// The response shape returned by a query/filter builder.
abstract class SupabaseResponseLike {
  Object? get data;
  Object? get error;
  int? get count;
}

/// Storage bucket surface used by the storage plugin.
abstract class SupabaseStorageBucketLike {
  Future<SupabaseSignedUrlResult> createSignedUrl(String path, int expiresIn);

  Future<SupabaseSignedUrlListResult> createSignedUrls(
    List<String> paths,
    int expiresIn,
  );

  Future<SupabaseUploadResult> upload(
    String path,
    List<int> fileBytes, {
    String? contentType,
    String? cacheControl,
  });

  Future<SupabaseRemoveResult> remove(List<String> paths);

  Future<SupabaseExistsResult> exists(String path);

  Future<SupabaseDownloadResult> download(String path);

  /// List objects under an optional prefix (used by storage GC).
  Future<SupabaseListResult> list([String? prefix]);
}

/// A list-objects result entry.
abstract class SupabaseStorageObject {
  String get key;
  int get size;
  String? get lastModifiedAt;
}

/// A list-objects result.
abstract class SupabaseListResult {
  List<SupabaseStorageObject>? get data;
  Object? get error;
}

/// A signed URL result.
abstract class SupabaseSignedUrlResult {
  String? get signedUrl;
  Object? get error;
}

/// A batch signed URL result.
abstract class SupabaseSignedUrlListResult {
  List<SupabaseSignedUrlResult>? get data;
  Object? get error;
}

/// An upload result.
abstract class SupabaseUploadResult {
  Object? get data;
  Object? get error;
}

/// A remove result.
abstract class SupabaseRemoveResult {
  Object? get data;
  Object? get error;
  String? get message;
}

/// An exists result.
abstract class SupabaseExistsResult {
  bool? get data;
  Object? get error;
  String? get message;
}

/// A download result.
abstract class SupabaseDownloadResult {
  List<int>? get data;
  Object? get error;
  String? get message;
}

/// The storage client surface used by the storage plugin.
abstract class SupabaseStorageClientLike {
  SupabaseStorageBucketLike from(String bucket);
}

/// The top-level Supabase client surface used by both plugins.
abstract class SupabaseClientLike {
  SupabaseQueryBuilderLike from(String table);
  SupabaseStorageClientLike get storage;
  Future<SupabaseRpcResponse> rpc(
    String functionName, {
    Map<String, dynamic>? params,
  });
}

/// An RPC response.
abstract class SupabaseRpcResponse {
  Object? get data;
  Object? get error;
}

/// Factory that builds a [SupabaseClientLike] from credentials.
typedef SupabaseClientFactory = SupabaseClientLike Function(
  String url,
  String key,
);
