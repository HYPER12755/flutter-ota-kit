import 'bundle_unit_of_work.dart';
import 'bundle_unit_of_work_store.dart';
import 'calculate_pagination.dart';
import 'types.dart';

const List<String> _replaceOnUpdateKeys = ['patches', 'targetCohorts'];
const DatabaseBundleQueryOrder _defaultDescOrder =
    DatabaseBundleQueryOrder(field: 'id', direction: 'desc');

int? _normalizePage(int? value) {
  if (value == null || value < 1) return null;
  return value;
}

/// Deep-merge a bundle patch onto a base bundle, replacing array fields
/// specified by [replaceKeys] rather than concatenating them.
Bundle mergeBundleUpdate(Bundle base, Map<String, Object?> patch) {
  final baseMap = base.toJson();
  for (final key in patch.keys) {
    final srcValue = patch[key];
    if (_replaceOnUpdateKeys.contains(key)) {
      baseMap[key] = srcValue;
    } else if (srcValue != null) {
      baseMap[key] = srcValue;
    }
  }
  return Bundle.fromJson(baseMap);
}

DatabaseBundleIdFilter _mergeIdFilter(
  DatabaseBundleIdFilter? base,
  DatabaseBundleIdFilter patch,
) {
  return DatabaseBundleIdFilter(
    eq: patch.eq ?? base?.eq,
    gt: patch.gt ?? base?.gt,
    gte: patch.gte ?? base?.gte,
    lt: patch.lt ?? base?.lt,
    lte: patch.lte ?? base?.lte,
    ins: patch.ins ?? base?.ins,
  );
}

DatabaseBundleQueryWhere _mergeWhereWithIdFilter(
  DatabaseBundleQueryWhere? where,
  DatabaseBundleIdFilter idFilter,
) {
  return DatabaseBundleQueryWhere(
    channel: where?.channel,
    platform: where?.platform,
    enabled: where?.enabled,
    id: _mergeIdFilter(where?.id, idFilter),
    targetAppVersion: where?.targetAppVersion,
    targetAppVersionIn: where?.targetAppVersionIn,
    targetAppVersionNotNull: where?.targetAppVersionNotNull,
    fingerprintHash: where?.fingerprintHash,
  );
}

class _CursorPageQuery {
  const _CursorPageQuery({
    required this.reverseData,
    required this.where,
    required this.orderBy,
  });

  final bool reverseData;
  final DatabaseBundleQueryWhere where;
  final DatabaseBundleQueryOrder orderBy;
}

_CursorPageQuery _buildCursorPageQuery(
  DatabaseBundleQueryWhere? where,
  DatabaseBundleCursor cursor,
  DatabaseBundleQueryOrder orderBy,
) {
  final direction = orderBy.direction;

  if (cursor.after != null) {
    return _CursorPageQuery(
      reverseData: false,
      where: _mergeWhereWithIdFilter(
        where,
        DatabaseBundleIdFilter(
          lt: direction == 'desc' ? cursor.after : null,
          gt: direction == 'asc' ? cursor.after : null,
        ),
      ),
      orderBy: orderBy,
    );
  }

  if (cursor.before != null) {
    return _CursorPageQuery(
      reverseData: true,
      where: _mergeWhereWithIdFilter(
        where,
        DatabaseBundleIdFilter(
          gt: direction == 'desc' ? cursor.before : null,
          lt: direction == 'asc' ? cursor.before : null,
        ),
      ),
      orderBy: DatabaseBundleQueryOrder(
        field: orderBy.field,
        direction: direction == 'desc' ? 'asc' : 'desc',
      ),
    );
  }

  return _CursorPageQuery(
    reverseData: false,
    where: where ?? const DatabaseBundleQueryWhere(),
    orderBy: orderBy,
  );
}

DatabaseBundleQueryWhere _buildCountBeforeWhere(
  DatabaseBundleQueryWhere? where,
  String firstBundleId,
  DatabaseBundleQueryOrder orderBy,
) {
  return _mergeWhereWithIdFilter(
    where,
    DatabaseBundleIdFilter(
      gt: orderBy.direction == 'desc' ? firstBundleId : null,
      lt: orderBy.direction == 'asc' ? firstBundleId : null,
    ),
  );
}

Paginated<List<Bundle>> _createPaginatedResult(
  int total,
  int limit,
  int startIndex,
  List<Bundle> data,
) {
  final pagination = calculatePagination(total, limit: limit, offset: startIndex);
  final nextCursor =
      data.isNotEmpty && startIndex + data.length < total ? data.last.id : null;
  final previousCursor =
      data.isNotEmpty && startIndex > 0 ? data.first.id : null;

  return Paginated(
    data: data,
    pagination: PaginationInfo(
      total: pagination.total,
      hasNextPage: pagination.hasNextPage,
      hasPreviousPage: pagination.hasPreviousPage,
      currentPage: pagination.currentPage,
      totalPages: pagination.totalPages,
      nextCursor: nextCursor,
      previousCursor: previousCursor,
    ),
  );
}

DatabaseBundleQueryOptions _expandLimitForUnitOfWork(
  DatabaseBundleQueryOptions options,
  BundleUnitOfWork unitOfWork,
) {
  final extra = unitOfWork.listFetchExtraCount();
  if (extra == 0) return options;
  return DatabaseBundleQueryOptions(
    where: options.where,
    limit: options.limit + extra,
    page: options.page,
    offset: options.offset,
    cursor: options.cursor,
    orderBy: options.orderBy,
  );
}

PaginationInfo _adjustPaginationTotal(
  PaginationInfo pagination, {
  required int limit,
  required int totalDelta,
}) {
  if (totalDelta == 0) return pagination;
  final total = (pagination.total + totalDelta).clamp(0, 0x7FFFFFFF);
  final hasPreviousPage = pagination.currentPage > 1;
  final hasNextPage = pagination.currentPage * limit < total;
  return PaginationInfo(
    total: total,
    hasNextPage: hasNextPage,
    hasPreviousPage: hasPreviousPage,
    currentPage: pagination.currentPage,
    totalPages: total == 0 ? 0 : (total / limit).ceil(),
    nextCursor: pagination.nextCursor,
    previousCursor: pagination.previousCursor,
  );
}

/// The underlying database methods a plugin must implement.
abstract class AbstractDatabasePlugin {
  bool get supportsCursorPagination => false;

  Future<Bundle?> getBundleById(String bundleId);

  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args);

  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  );

  Future<List<String>> getChannels();

  Future<void> commitBundle({
    required List<BundleChange> changedSets,
  });

  Future<void> onUnmount();
}

/// Configuration for [createDatabasePlugin].
class CreateDatabasePluginOptions<TConfig> {
  const CreateDatabasePluginOptions({
    required this.name,
    required this.factory,
  });

  final String name;
  final AbstractDatabasePlugin Function(TConfig config) factory;
}

/// Double-curried factory that creates a [DatabasePlugin] with lazy
/// initialization, UnitOfWork integration, and hook support.
///
/// Usage:
/// ```dart
/// final supabaseDatabase = createDatabasePlugin<SupabaseConfig>(
///   name: 'supabaseDatabase',
///   factory: (config) => SupabaseDatabaseImpl(config),
/// );
/// // First curry: config + hooks → factory
/// final createDb = supabaseDatabase(config, hooks);
/// // Second curry: new plugin instance
/// final db = createDb();
/// ```
DatabasePlugin Function() Function(TConfig config, [DatabasePluginHooks? hooks])
    createDatabasePlugin<TConfig>({
  required String name,
  required AbstractDatabasePlugin Function(TConfig config) factory,
}) {
  return (TConfig config, [DatabasePluginHooks? hooks]) {
    AbstractDatabasePlugin? cachedMethods;
    AbstractDatabasePlugin getMethods() {
      cachedMethods ??= factory(config);
      return cachedMethods!;
    }

    return () {
      final instanceUnitOfWork = BundleUnitOfWork();

      BundleUnitOfWork getMutationUnitOfWork(
              Map<String, Object?>? context) =>
          getRequestBundleUnitOfWork(context) ?? instanceUnitOfWork;

      Future<Paginated<List<Bundle>>> runGetBundles(
        DatabaseBundleQueryOptions options,
      ) =>
          getMethods().getBundles(options);

      Future<Paginated<List<Bundle>>> getBundlesWithLegacyCursorFallback(
        DatabaseBundleQueryOptions options,
      ) async {
        final orderBy = options.orderBy ?? _defaultDescOrder;
        final baseWhere = options.where;

        final totalResult = await runGetBundles(
          DatabaseBundleQueryOptions(
            where: baseWhere,
            limit: 1,
            offset: 0,
            orderBy: orderBy,
          ),
        );
        final total = totalResult.pagination.total;

        if (options.cursor?.after == null && options.cursor?.before == null) {
          final firstPage = await runGetBundles(
            DatabaseBundleQueryOptions(
              where: baseWhere,
              limit: options.limit,
              offset: 0,
              orderBy: orderBy,
            ),
          );
          return _createPaginatedResult(total, options.limit, 0, firstPage.data);
        }

        final cursorQuery = _buildCursorPageQuery(
          baseWhere,
          options.cursor!,
          orderBy,
        );
        final cursorPage = await runGetBundles(
          DatabaseBundleQueryOptions(
            where: cursorQuery.where,
            limit: options.limit,
            offset: 0,
            orderBy: cursorQuery.orderBy,
          ),
        );
        final data = cursorQuery.reverseData
            ? cursorPage.data.reversed.toList()
            : cursorPage.data;

        if (data.isEmpty) {
          return Paginated(
            data: data,
            pagination: PaginationInfo(
              total: total,
              hasNextPage: false,
              hasPreviousPage: false,
              currentPage: 1,
              totalPages: 0,
              nextCursor: options.cursor?.before,
              previousCursor: options.cursor?.after,
            ),
          );
        }

        final firstBundleId = data.first.id;
        final countBeforeResult = await runGetBundles(
          DatabaseBundleQueryOptions(
            where: _buildCountBeforeWhere(baseWhere, firstBundleId, orderBy),
            limit: 1,
            offset: 0,
            orderBy: orderBy,
          ),
        );

        return _createPaginatedResult(
          total,
          options.limit,
          countBeforeResult.pagination.total,
          data,
        );
      }

      // Build the plugin methods.
      return _DatabasePluginImpl(
        name: name,
        getMethods: getMethods,
        getMutationUnitOfWork: getMutationUnitOfWork,
        instanceUnitOfWork: instanceUnitOfWork,
        runGetBundles: runGetBundles,
        getBundlesWithLegacyCursorFallback: getBundlesWithLegacyCursorFallback,
        hooks: hooks,
      ) as DatabasePlugin;
    };
  };
}

/// Internal implementation of DatabasePlugin.
class _DatabasePluginImpl implements DatabasePlugin {
  _DatabasePluginImpl({
    required this.name,
    required this.getMethods,
    required this.getMutationUnitOfWork,
    required this.instanceUnitOfWork,
    required this.runGetBundles,
    required this.getBundlesWithLegacyCursorFallback,
    this.hooks,
  });

  @override
  final String name;
  final AbstractDatabasePlugin Function() getMethods;
  final BundleUnitOfWork Function(Map<String, Object?>?) getMutationUnitOfWork;
  final BundleUnitOfWork instanceUnitOfWork;
  final Future<Paginated<List<Bundle>>> Function(DatabaseBundleQueryOptions)
      runGetBundles;
  final Future<Paginated<List<Bundle>>> Function(DatabaseBundleQueryOptions)
      getBundlesWithLegacyCursorFallback;
  final DatabasePluginHooks? hooks;

  @override
  Future<void> onUnmount() => getMethods().onUnmount();

  @override
  Future<List<String>> getChannels() => getMethods().getChannels();

  @override
  Future<Bundle?> getBundleById(String bundleId) async {
    final requestUoW =
        getRequestBundleUnitOfWork(null); // context not passed through here
    if (requestUoW != null) {
      return requestUoW.getById(bundleId, () =>
          getMethods().getBundleById(bundleId));
    }
    final pending = instanceUnitOfWork.peekChanged(bundleId);
    if (pending is TrackedBundleFound) return pending.value;
    return getMethods().getBundleById(bundleId);
  }

  @override
  Future<UpdateInfo?> getUpdateInfo(GetBundlesArgs args) async {
    final methods = getMethods();
    return methods.getUpdateInfo(args);
  }

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) async {
    final methods = getMethods();
    final unitOfWork = getMutationUnitOfWork(null);
    final shouldOverlay = instanceUnitOfWork.hasChanges();
    final normalizedOptions = DatabaseBundleQueryOptions(
      where: options.where,
      limit: options.limit,
      page: _normalizePage(options.page),
      cursor: options.cursor,
      orderBy: options.orderBy ?? _defaultDescOrder,
    );

    Paginated<List<Bundle>> overlayResult(Paginated<List<Bundle>> result) {
      return Paginated(
        data: unitOfWork.overlayList(
          result.data,
          limit: normalizedOptions.limit,
          orderBy: normalizedOptions.orderBy,
          where: normalizedOptions.where,
        ),
        pagination: _adjustPaginationTotal(
          result.pagination,
          limit: normalizedOptions.limit,
          totalDelta: unitOfWork.totalDelta(normalizedOptions.where),
        ),
      );
    }

    if (normalizedOptions.page != null) {
      final page = normalizedOptions.page!;
      final requestedOffset = (page - 1) * normalizedOptions.limit;
      final fetchOptions = _expandLimitForUnitOfWork(normalizedOptions, unitOfWork);
      var pageResult = await runGetBundles(
        DatabaseBundleQueryOptions(
          where: fetchOptions.where,
          limit: fetchOptions.limit,
          offset: requestedOffset,
          orderBy: fetchOptions.orderBy,
        ),
      );

      final total = pageResult.pagination.total;
      final totalPages =
          total == 0 ? 0 : (total / normalizedOptions.limit).ceil();
      final maxOffset =
          totalPages == 0 ? 0 : (totalPages - 1) * normalizedOptions.limit;
      final resolvedOffset =
          requestedOffset < maxOffset ? requestedOffset : maxOffset;

      if (resolvedOffset != requestedOffset) {
        pageResult = await runGetBundles(
          DatabaseBundleQueryOptions(
            where: fetchOptions.where,
            limit: fetchOptions.limit,
            offset: resolvedOffset,
            orderBy: fetchOptions.orderBy,
          ),
        );
      }

      final result = _createPaginatedResult(
        total,
        normalizedOptions.limit,
        resolvedOffset,
        pageResult.data,
      );
      return shouldOverlay ? overlayResult(result) : result;
    }

    if (methods.supportsCursorPagination) {
      final fetchOptions = _expandLimitForUnitOfWork(normalizedOptions, unitOfWork);
      final result = await runGetBundles(fetchOptions);
      return shouldOverlay ? overlayResult(result) : result;
    }

    final result = await getBundlesWithLegacyCursorFallback(
      shouldOverlay
          ? _expandLimitForUnitOfWork(normalizedOptions, unitOfWork)
          : normalizedOptions,
    );
    return shouldOverlay ? overlayResult(result) : result;
  }

  @override
  Future<void> commitBundle() async {
    final methods = getMethods();
    final unitOfWork = getMutationUnitOfWork(null);
    await methods.commitBundle(
      changedSets: unitOfWork.changedSets(),
    );
    unitOfWork.clear();
    final cb = hooks?.onDatabaseUpdated;
    if (cb != null) await cb();
  }

  @override
  Future<void> updateBundle(
    String targetBundleId,
    Map<String, Object?> newBundle,
  ) async {
    final unitOfWork = getMutationUnitOfWork(null);
    final current = await unitOfWork.getById(targetBundleId, () =>
        getMethods().getBundleById(targetBundleId));
    if (current == null) {
      throw StateError('targetBundleId not found');
    }
    final updated = mergeBundleUpdate(current, newBundle);
    unitOfWork.markUpdate(updated);
  }

  @override
  Future<void> appendBundle(Bundle insertBundle) async {
    getMutationUnitOfWork(null).markInsert(insertBundle);
  }

  @override
  Future<void> deleteBundle(Bundle deleteBundle) async {
    getMutationUnitOfWork(null).markDelete(deleteBundle);
  }
}
