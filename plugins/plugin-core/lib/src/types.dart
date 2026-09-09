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
  const DatabaseBundleQueryOrder({this.field = 'id', this.direction = 'desc'});

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

/// Database abstraction for bundle storage and querying.
///
/// Implementations handle the backend-specific SQL/API calls while the
/// plugin-core layer manages pagination, unit-of-work tracking, and
/// hook callbacks.
///
/// Lifecycle:
/// 1. Plugin is created via [createDatabasePlugin] factory.
/// 2. Methods are called by the CLI (deploy, migrate, bundle management)
///    or the console (bundle listing, editing).
/// 3. [onUnmount] is called when the plugin is disposed.
abstract class DatabasePlugin {
  /// Human-readable plugin name (e.g. `supabaseDatabase`).
  String get name;

  /// List all distinct channel values across all bundles.
  Future<List<String>> getChannels();

  /// Fetch a single bundle by its UUID. Returns null if not found.
  Future<Bundle?> getBundleById(String bundleId);

  /// Resolve the update decision for a device's update-check request.
  ///
  /// Returns the eligible [UpdateInfo] (update or rollback), or null if
  /// the device is already on the latest bundle.
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args);

  /// Query bundles with filtering, pagination, and ordering.
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  );

  /// Update specific fields of an existing bundle.
  ///
  /// [newBundle] contains only the changed fields (partial update).
  Future<void> updateBundle(
    String targetBundleId,
    Map<String, Object?> newBundle,
  );

  /// Insert a new bundle. The bundle is staged in the unit-of-work
  /// until [commitBundle] is called.
  Future<void> appendBundle(Bundle insertBundle);

  /// Flush all staged changes (inserts, updates, deletes) to the backend.
  Future<void> commitBundle();

  /// Delete a bundle and its associated storage artifacts.
  Future<void> deleteBundle(Bundle deleteBundle);

  /// Release resources (close connections, cancel timers).
  Future<void> onUnmount();
}

/// Optional lifecycle hooks for database plugin events.
class DatabasePluginHooks {
  const DatabasePluginHooks({this.onDatabaseUpdated});

  /// Called after a bundle mutation is committed to the database.
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

/// Profiles for accessing storage in different contexts.
///
/// A storage plugin may support one or both profiles:
/// - [node]: For CLI/deploy operations (file upload, delete, list).
/// - [runtime]: For device update-check operations (signed URLs, manifest read).
class StoragePluginProfiles {
  const StoragePluginProfiles({this.node, this.runtime});

  /// Node profile for CLI/deploy operations. Null if not supported.
  final NodeStorageProfile? node;

  /// Runtime profile for device update-checks. Null if not supported.
  final RuntimeStorageProfile? runtime;

  /// Whether this plugin supports CLI/deploy operations.
  bool get hasNode => node != null;

  /// Whether this plugin supports device update-check operations.
  bool get hasRuntime => runtime != null;
}

/// Storage backend abstraction for artifact upload/download.
///
/// Each backend (S3, R2, Supabase Storage, PocketBase) implements this
/// interface to provide a unified storage API.
///
/// Storage URIs follow the scheme defined in [parseStorageUri]:
/// `protocol://bucket/key` where protocol is `s3`, `r2`, `supabase-storage`,
/// or `pocketbase`.
abstract class StoragePlugin {
  /// Human-readable plugin name (e.g. `s3Storage`, `r2Storage`).
  String get name;

  /// Protocol scheme this plugin handles (e.g. `s3`, `r2`, `supabase-storage`).
  String get supportedProtocol;

  /// Access profiles for node (CLI) and runtime (device) operations.
  StoragePluginProfiles get profiles;
}

/// Optional lifecycle hooks for storage plugin events.
class StoragePluginHooks {
  const StoragePluginHooks({this.onStorageUploaded});

  /// Called after a file is successfully uploaded to storage.
  final Future<void> Function()? onStorageUploaded;
}

// ---------------------------------------------------------------------------
// Build plugin
// ---------------------------------------------------------------------------

/// Result of a successful build operation.
class BuildPluginResult {
  const BuildPluginResult({
    required this.buildPath,
    required this.bundleId,
    this.stdout,
  });

  /// Path to the built artifact (e.g. `build/app/outputs/flutter-apk/app-release.apk`).
  final String buildPath;

  /// Generated bundle UUID for this build.
  final String bundleId;

  /// Raw build output (stdout + stderr combined).
  final String? stdout;
}

/// Build system abstraction for creating app artifacts.
///
/// Implementations handle the platform-specific build commands (Gradle,
/// Xcodebuild) while the plugin-core layer manages versioning and artifact
/// packaging.
abstract class BuildPlugin {
  /// Human-readable plugin name (e.g. `androidBuild`, `iosBuild`).
  String get name;

  /// Execute the build for the given [platform] and return the artifact path.
  Future<BuildPluginResult> build(Platform platform);

  /// Pre-build hook (e.g. clean, dependency resolution).
  Future<void> prebuild(Platform platform);

  /// Post-build hook (e.g. signing, obfuscation).
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

  static const bool enabled = false;
  final String? privateKeyPath;
}

class SigningConfigEnabled {
  const SigningConfigEnabled({required this.privateKeyPath});

  static const bool enabled = true;
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
///
/// Plugins may attach metadata to this map during processing. Known keys:
///
/// - `bundleId` (String) — Current bundle ID being processed
/// - `channel` (String) — Target release channel
/// - `platform` (String) — Target platform (`ios`, `android`)
/// - `appVersion` (String) — Current app version (semver)
/// - `fingerprintHash` (String) — Device fingerprint hash
/// - `cohort` (String) — Rollout cohort identifier
/// - `storageUri` (String) — Resolved storage URI for the artifact
/// - `signedUrl` (String) — Pre-signed download URL
///
/// Extensions should use namespaced keys (e.g. `myPlugin.fieldName`) to
/// avoid collisions.
typedef HotUpdaterContext = Map<String, Object?>;

/// Context for resolving storage URIs to download URLs.
///
/// Inherits all keys from [HotUpdaterContext] and adds:
///
/// - `storageProtocol` (String) — Expected protocol (`s3`, `r2`, `supabase-storage`, etc.)
/// - `storageBucket` (String) — Target bucket name
typedef StorageResolveContext = HotUpdaterContext;
