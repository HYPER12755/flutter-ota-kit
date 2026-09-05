/// PocketBase-backed [DatabasePlugin] implementation.
library;

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';

import 'pocketbase_bundle_mapper.dart';
import 'pocketbase_client.dart';
import 'pocketbase_config.dart';

/// Configuration for the PocketBase database plugin.
typedef PocketBaseDatabaseConfig = PocketBaseConfig;

/// PocketBase-backed [AbstractDatabasePlugin] implementation.
class _PocketBaseDatabase implements AbstractDatabasePlugin {
  _PocketBaseDatabase(this.config, this.client);

  final PocketBaseConfig config;
  final PocketBaseClient client;

  static _PocketBaseDatabase build(PocketBaseConfig config) {
    final client = config.clientFactory != null
        ? config.clientFactory!(
            config.url,
            config.adminEmail,
            config.adminPassword,
          )
        : PocketBaseClient(config.url);
    client.adminCredentials(config.adminEmail, config.adminPassword);
    return _PocketBaseDatabase(config, client);
  }

  @override
  bool get supportsCursorPagination => false;

  // ----- Channels -----

  @override
  Future<List<String>> getChannels() async {
    final res = await client.listRecords<dynamic>(
      config.channelsCollection,
      (j) => j,
      perPage: 200,
      sort: 'name',
    );
    return res.items
        .map((j) => (j as Map)['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ----- Single bundle -----

  @override
  Future<Bundle?> getBundleById(String bundleId) async {
    final row = await client.getRecord<PocketBaseBundleRow>(
      config.bundlesCollection,
      bundleId,
      PocketBaseBundleRow.fromJson,
    );
    return row == null ? null : mapRowToBundle(row);
  }

  @override
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args) async {
    final filter = _buildFilter(
      channel: args.channel,
      platform: args.platform,
      enabled: true,
    );
    final list = await client.listRecords<PocketBaseBundleRow>(
      config.bundlesCollection,
      PocketBaseBundleRow.fromJson,
      filter: filter.isEmpty ? null : filter,
      sort: '-created',
      perPage: 1,
    );
    if (list.items.isEmpty) return null;
    final bundle = mapRowToBundle(list.items.first);
    return UpdateInfo(
      id: bundle.id,
      shouldForceUpdate: bundle.shouldForceUpdate,
      message: bundle.message,
      status: UpdateStatus.update,
      storageUri: bundle.storageUri,
      fileHash: bundle.fileHash,
    );
  }

  // ----- Query bundles -----

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) async {
    final where = options.where;
    final filter = _buildFilter(
      channel: where?.channel,
      platform: where?.platform,
      enabled: where?.enabled,
      idEq: where?.id?.eq,
      idGt: where?.id?.gt,
      idLt: where?.id?.lt,
      targetAppVersion: where?.targetAppVersion,
      fingerprintHash: where?.fingerprintHash,
    );
    final orderField = options.orderBy?.field ?? 'id';
    final desc = options.orderBy?.direction != 'asc';
    // PB sort syntax: `field` for asc, `-field` for desc.
    final sort = (desc ? '-' : '') + orderField;
    final limit = options.limit == 0 ? 50 : options.limit;
    final page = (options.offset ?? 0) ~/ limit + 1;
    final list = await client.listRecords<PocketBaseBundleRow>(
      config.bundlesCollection,
      PocketBaseBundleRow.fromJson,
      filter: filter.isEmpty ? null : filter,
      sort: sort,
      page: page,
      perPage: limit,
    );
    final total = list.totalItems;
    final totalPages = list.totalPages == 0 ? 1 : list.totalPages;
    final currentPage = list.page;
    final hasNextPage = currentPage < totalPages;
    final hasPreviousPage = currentPage > 1;
    return Paginated(
      data: list.items.map(mapRowToBundle).toList(),
      pagination: PaginationInfo(
        total: total,
        hasNextPage: hasNextPage,
        hasPreviousPage: hasPreviousPage,
        currentPage: currentPage,
        totalPages: totalPages,
        nextCursor: list.items.isNotEmpty && hasNextPage
            ? list.items.last.id
            : null,
        previousCursor: list.items.isNotEmpty && hasPreviousPage
            ? list.items.first.id
            : null,
      ),
    );
  }

  // ----- Mutations (UnitOfWork) -----

  @override
  Future<void> commitBundle({required List<BundleChange> changedSets}) async {
    for (final change in changedSets) {
      switch (change.operation) {
        case BundleChangeOperation.insert:
          final row = _rowFromBundle(change.data);
          final exists = await client.recordExists(
            config.bundlesCollection,
            change.data.id,
          );
          if (exists) {
            // The storage plugin may have pre-created the record (to host
            // the artifact file). Update the metadata fields rather than
            // failing on a duplicate id.
            await client.updateRecord<dynamic>(
              config.bundlesCollection,
              change.data.id,
              row.toCreateJson(),
              (j) => j,
            );
          } else {
            await client.createRecord<dynamic>(
              config.bundlesCollection,
              row.toCreateJson(),
              (j) => j,
            );
          }
          break;
        case BundleChangeOperation.update:
          final patch = _buildUpdatePatch(change.data);
          if (patch.isEmpty) continue;
          await client.updateRecord<dynamic>(
            config.bundlesCollection,
            change.data.id,
            patch,
            (j) => j,
          );
          break;
        case BundleChangeOperation.delete:
          await client.deleteRecord(config.bundlesCollection, change.data.id);
          break;
      }
    }
  }

  @override
  Future<void> onUnmount() async {
    client.close();
  }

  // ----- Helpers -----

  PocketBaseBundleRow _rowFromBundle(Bundle v) => PocketBaseBundleRow(
    id: v.id,
    channel: v.channel,
    enabled: v.enabled,
    platform: v.platform.value,
    shouldForceUpdate: v.shouldForceUpdate,
    fileHash: v.fileHash,
    storageUri: v.storageUri,
    rolloutCohortCount: v.rolloutCohortCount ?? 1000,
    gitCommitHash: v.gitCommitHash,
    message: v.message,
    fingerprintHash: v.fingerprintHash,
    targetAppVersion: v.targetAppVersion,
    manifestStorageUri: v.manifestStorageUri,
    manifestFileHash: v.manifestFileHash,
    assetBaseStorageUri: v.assetBaseStorageUri,
    targetCohorts: v.targetCohorts,
    metadata: v.metadata?.toJson(),
  );

  String _buildFilter({
    String? channel,
    Platform? platform,
    bool? enabled,
    String? idEq,
    String? idGt,
    String? idLt,
    String? targetAppVersion,
    String? fingerprintHash,
  }) {
    final clauses = <String>[];
    if (channel != null && channel.isNotEmpty) {
      clauses.add('channel = "${_escape(channel)}"');
    }
    if (platform != null) {
      clauses.add('platform = "${_escape(platform.value)}"');
    }
    if (enabled != null) {
      clauses.add('enabled = ${enabled ? 'true' : 'false'}');
    }
    if (idEq != null) clauses.add('id = "${_escape(idEq)}"');
    if (idGt != null) clauses.add('id > "${_escape(idGt)}"');
    if (idLt != null) clauses.add('id < "${_escape(idLt)}"');
    if (targetAppVersion != null) {
      clauses.add('target_app_version = "${_escape(targetAppVersion)}"');
    }
    if (fingerprintHash != null) {
      clauses.add('fingerprint_hash = "${_escape(fingerprintHash)}"');
    }
    return clauses.join(' && ');
  }

  String _escape(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  Map<String, dynamic> _buildUpdatePatch(Bundle v) => {
    if (v.channel.isNotEmpty) 'channel': v.channel,
    'enabled': v.enabled,
    'platform': v.platform.value,
    'should_force_update': v.shouldForceUpdate,
    'rollout_cohort_count': v.rolloutCohortCount ?? 1000,
    'file_hash': v.fileHash,
    'storage_uri': v.storageUri,
    if (v.gitCommitHash != null) 'git_commit_hash': v.gitCommitHash,
    if (v.message != null) 'message': v.message,
    if (v.fingerprintHash != null) 'fingerprint_hash': v.fingerprintHash,
    if (v.targetAppVersion != null) 'target_app_version': v.targetAppVersion,
    if (v.manifestStorageUri != null)
      'manifest_storage_uri': v.manifestStorageUri,
    if (v.manifestFileHash != null) 'manifest_file_hash': v.manifestFileHash,
    if (v.assetBaseStorageUri != null)
      'asset_base_storage_uri': v.assetBaseStorageUri,
    if (v.targetCohorts != null) 'target_cohorts': v.targetCohorts,
    if (v.metadata != null) 'metadata': v.metadata!.toJson(),
  };
}

/// Build a `pocketbaseDatabase` plugin factory.
final pocketbaseDatabase = createDatabasePlugin<PocketBaseConfig>(
  name: 'pocketbaseDatabase',
  factory: _PocketBaseDatabase.build,
);
