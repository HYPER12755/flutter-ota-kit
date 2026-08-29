import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
export 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show Bundle, GetBundlesArgs, Platform, UpdateInfo;

// ---------------------------------------------------------------------------
// Pagination
// ---------------------------------------------------------------------------

class PaginationInfo {
  const PaginationInfo({
    required this.total,
    required this.hasNextPage,
    required this.hasPreviousPage,
    required this.currentPage,
    required this.totalPages,
    this.nextCursor,
    this.previousCursor,
  });

  final int total;
  final bool hasNextPage;
  final bool hasPreviousPage;
  final int currentPage;
  final int totalPages;
  final String? nextCursor;
  final String? previousCursor;

  @override
  String toString() =>
      'PaginationInfo(total: $total, hasNextPage: $hasNextPage, '
      'hasPreviousPage: $hasPreviousPage, currentPage: $currentPage, '
      'totalPages: $totalPages)';
}

class Paginated<T> {
  const Paginated({required this.data, required this.pagination});

  final T data;
  final PaginationInfo pagination;
}

typedef PaginatedResult = Paginated<List<Bundle>>;

// ---------------------------------------------------------------------------
// Database query types
// ---------------------------------------------------------------------------

class DatabaseBundleIdFilter {
  const DatabaseBundleIdFilter({
    this.eq,
    this.gt,
    this.gte,
    this.lt,
    this.lte,
    this.ins,
  });

  final String? eq;
  final String? gt;
  final String? gte;
  final String? lt;
  final String? lte;
  final List<String>? ins;
}

class DatabaseBundleQueryWhere {
  const DatabaseBundleQueryWhere({
    this.channel,
    this.platform,
    this.enabled,
    this.id,
    this.targetAppVersion,
    this.targetAppVersionIn,
    this.targetAppVersionNotNull,
    this.fingerprintHash,
  });

  final String? channel;
  final Platform? platform;
  final bool? enabled;
  final DatabaseBundleIdFilter? id;
  final String? targetAppVersion;
  final List<String>? targetAppVersionIn;
  final bool? targetAppVersionNotNull;
  final String? fingerprintHash;
}

class DatabaseBundleQueryOrder {
  const DatabaseBundleQueryOrder({
    this.field = 'id',
    this.direction = 'desc',
  });

  final String field;
  final String direction;
}

class DatabaseBundleCursor {
  const DatabaseBundleCursor({this.after, this.before});

  /// Fetch the next window after this bundle ID.
  final String? after;

  /// Fetch the previous window before this bundle ID.
  final String? before;
}

class DatabaseBundleQueryOptions {
  const DatabaseBundleQueryOptions({
    this.where,
    this.limit = 20,
    this.page,
    this.offset,
    this.cursor,
    this.orderBy,
  });

  final DatabaseBundleQueryWhere? where;
  final int limit;
  final int? page;

  /// Computed by the [createDatabasePlugin] wrapper from [page] (or cursor);
  /// absent only when using raw cursor pagination. Mirrors the TS
  /// `DatabaseBundleQueryOptions & { offset?: number }` contract.
  final int? offset;
  final DatabaseBundleCursor? cursor;
  final DatabaseBundleQueryOrder? orderBy;
}

// ---------------------------------------------------------------------------
// Database plugin
// ---------------------------------------------------------------------------

abstract class DatabasePlugin {
  String get name;

  Future<List<String>> getChannels();

  Future<Bundle?> getBundleById(String bundleId);

  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args);

  Future<Paginated<List<Bundle>>> getBundles(
      DatabaseBundleQueryOptions options);

  Future<void> updateBundle(String targetBundleId, Map<String, Object?> newBundle);

  Future<void> appendBundle(Bundle insertBundle);

  Future<void> commitBundle();

  Future<void> deleteBundle(Bundle deleteBundle);

  Future<void> onUnmount();
}

class DatabasePluginHooks {
  const DatabasePluginHooks({this.onDatabaseUpdated});

  final Future<void> Function()? onDatabaseUpdated;
}

// ---------------------------------------------------------------------------
// Storage plugin
// ---------------------------------------------------------------------------

class StorageObject {
  const StorageObject({
    required this.key,
    required this.storageUri,
    required this.size,
    this.lastModifiedAt,
  });

  final String key;
  final String storageUri;
  final int size;
  final DateTime? lastModifiedAt;
}

/// Node (CLI/deploy) storage profile — filesystem-aware operations.
abstract class NodeStorageProfile {
  /// Upload a local file and return the storage URI.
  Future<Map<String, String>> upload(String key, String filePath);

  /// Check if an object exists and is signable.
  Future<bool> exists(String storageUri);

  /// Delete an object by storage URI.
  Future<void> delete(String storageUri);

  /// Download an object to a local file path.
  Future<void> downloadFile(String storageUri, String filePath);

  /// List objects under an optional prefix.
  Future<List<StorageObject>> listObjects([String? prefix]);

  /// Delete multiple objects by key.
  Future<void> deleteObjects(List<String> keys);
}

/// Runtime (update-check) storage profile — URL-oriented operations.
abstract class RuntimeStorageProfile {
  /// Get a signed download URL for the given storage URI.
  Future<Map<String, String>> getDownloadUrl(String storageUri);

  /// Read the content of a small text object (e.g. manifest).
  Future<String?> readText(String storageUri);
}

class StoragePluginProfiles {
  const StoragePluginProfiles({this.node, this.runtime});

  final NodeStorageProfile? node;
  final RuntimeStorageProfile? runtime;

  bool get hasNode => node != null;
  bool get hasRuntime => runtime != null;
}

abstract class StoragePlugin {
  String get name;
  String get supportedProtocol;
  StoragePluginProfiles get profiles;
}

class StoragePluginHooks {
  const StoragePluginHooks({this.onStorageUploaded});

  final Future<void> Function()? onStorageUploaded;
}

// ---------------------------------------------------------------------------
// Build plugin
// ---------------------------------------------------------------------------

class BuildPluginResult {
  const BuildPluginResult({
    required this.buildPath,
    required this.bundleId,
    this.stdout,
  });

  final String buildPath;
  final String bundleId;
  final String? stdout;
}

abstract class BuildPlugin {
  String get name;

  Future<BuildPluginResult> build(Platform platform);

  Future<void> prebuild(Platform platform);
  Future<void> postbuild(Platform platform);
}

// ---------------------------------------------------------------------------
// Android / iOS native build scheme types
// ---------------------------------------------------------------------------

class NativeBuildAndroidScheme {
  const NativeBuildAndroidScheme({
    this.variant = 'Release',
    this.aab = true,
    this.appModuleName = 'app',
    required this.packageName,
    this.applicationId,
  });

  final String variant;
  final bool aab;
  final String appModuleName;
  final String packageName;
  final String? applicationId;
}

class NativeBuildIosScheme {
  const NativeBuildIosScheme({
    required this.bundleIdentifier,
    this.platform = 'ios',
    required this.scheme,
    this.configuration = 'Release',
    this.destination,
    this.exportOptionsPlist,
    this.xcconfig,
    this.installPods = false,
    this.extraParams,
    this.exportExtraParams,
    this.simulator = false,
  });

  final String bundleIdentifier;
  final String platform;
  final String scheme;
  final String configuration;
  final List<String>? destination;
  final String? exportOptionsPlist;
  final String? xcconfig;
  final bool installPods;
  final List<String>? extraParams;
  final List<String>? exportExtraParams;
  final bool simulator;
}

class PlatformAndroidConfig {
  const PlatformAndroidConfig({
    this.androidManifestPaths,
    this.stringResourcePaths,
  });

  final List<String>? androidManifestPaths;
  final List<String>? stringResourcePaths;
}

class PlatformIosConfig {
  const PlatformIosConfig({this.infoPlistPaths});

  final List<String>? infoPlistPaths;
}

class PlatformConfig {
  const PlatformConfig({this.android, this.ios});

  final PlatformAndroidConfig? android;
  final PlatformIosConfig? ios;
}

class NativeBuildArgs {
  const NativeBuildArgs({this.android, this.ios});

  final Map<String, NativeBuildAndroidScheme>? android;
  final Map<String, NativeBuildIosScheme>? ios;
}

// ---------------------------------------------------------------------------
// Signing
// ---------------------------------------------------------------------------

class SigningConfigDisabled {
  const SigningConfigDisabled({this.privateKeyPath});

  final bool enabled = false;
  final String? privateKeyPath;
}

class SigningConfigEnabled {
  const SigningConfigEnabled({required this.privateKeyPath});

  final bool enabled = true;
  final String privateKeyPath;
}

// ---------------------------------------------------------------------------
// Fingerprint
// ---------------------------------------------------------------------------

class FingerprintExtraSourcesObject {
  const FingerprintExtraSourcesObject({this.ios, this.android});

  final List<String>? ios;
  final List<String>? android;
}

// ---------------------------------------------------------------------------
// ConfigInput — full hot-updater configuration
// ---------------------------------------------------------------------------

class ConfigInput {
  const ConfigInput({
    this.cacheDir,
    this.releaseChannel,
    this.updateStrategy = 'appVersion',
    this.compressStrategy = 'zip',
    this.fingerprint,
    this.patch,
    this.console,
    this.platform,
    this.nativeBuild,
    this.signing,
    required this.build,
    required this.storage,
    required this.database,
  });

  final String? cacheDir;
  final String? releaseChannel;
  final String updateStrategy;
  final String compressStrategy;
  final FingerprintConfig? fingerprint;
  final PatchConfig? patch;
  final ConsoleConfig? console;
  final PlatformConfig? platform;
  final NativeBuildArgs? nativeBuild;
  final Object? signing;
  final Future<BuildPlugin> Function(BasePluginArgs args) build;
  final Future<StoragePlugin> Function() storage;
  final Future<DatabasePlugin> Function() database;
}

class BasePluginArgs {
  const BasePluginArgs({required this.cwd});

  final String cwd;
}

class FingerprintConfig {
  const FingerprintConfig({
    this.extraSources,
    this.ignorePaths,
    this.debug = false,
  });

  final Object? extraSources;
  final List<String>? ignorePaths;
  final bool debug;
}

class PatchConfig {
  const PatchConfig({this.enabled = true, this.maxBaseBundles = 3});

  final bool enabled;
  final int maxBaseBundles;
}

class ConsoleConfig {
  const ConsoleConfig({this.gitUrl, this.port = 1422});

  final String? gitUrl;
  final int port;
}

class NativeBuildOptions {
  const NativeBuildOptions({
    this.outputPath,
    required this.interactive,
    this.message,
    this.scheme,
  });

  final String? outputPath;
  final bool interactive;
  final String? message;
  final String? scheme;
}

// ---------------------------------------------------------------------------
// Request context
// ---------------------------------------------------------------------------

/// Opaque context object carried through a request lifecycle.
/// In Dart we use a plain Map for extensibility.
typedef HotUpdaterContext = Map<String, Object?>;
typedef StorageResolveContext = HotUpdaterContext;
