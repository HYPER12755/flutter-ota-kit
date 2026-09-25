import 'calculate_pagination.dart';
import 'query_bundles.dart';
import 'types.dart';

/// Paginate a list of bundles using offset or cursor-based pagination.
///
/// Faithful port of hot-updater `paginateBundles.ts`.
Paginated<List<Bundle>> paginateBundles({
  required List<Bundle> bundles,
  required int limit,
  int? offset,
  DatabaseBundleCursor? cursor,
  DatabaseBundleQueryOrder? orderBy,
}) {
  final sortedBundles = sortBundles(bundles, orderBy);
  final direction = orderBy?.direction ?? 'desc';
  final total = sortedBundles.length;

  // Offset-based pagination
  if (offset != null) {
    final normalizedOffset = offset < 0 ? 0 : offset;
    final data = limit > 0
        ? sortedBundles.sublist(
            normalizedOffset,
            normalizedOffset + limit > total ? total : normalizedOffset + limit,
          )
        : sortedBundles.sublist(normalizedOffset);
    final pagination = calculatePagination(
      total,
      limit: limit,
      offset: normalizedOffset,
    );
    final nextCursor = data.isNotEmpty && normalizedOffset + data.length < total
        ? data.last.id
        : null;
    final previousCursor = data.isNotEmpty && normalizedOffset > 0
        ? data.first.id
        : null;

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

  // Cursor-based pagination
  List<Bundle> data;
  if (cursor?.after != null) {
    final candidates = sortedBundles.where((bundle) {
      return direction == 'desc'
          ? bundle.id.compareTo(cursor!.after!) < 0
          : bundle.id.compareTo(cursor!.after!) > 0;
    }).toList();
    data = limit > 0
        ? candidates.sublist(
            0,
            limit > candidates.length ? candidates.length : limit,
          )
        : candidates;
  } else if (cursor?.before != null) {
    final candidates = sortedBundles.where((bundle) {
      return direction == 'desc'
          ? bundle.id.compareTo(cursor!.before!) > 0
          : bundle.id.compareTo(cursor!.before!) < 0;
    }).toList();
    data = limit > 0
        ? candidates.sublist(
            candidates.length - limit > 0 ? candidates.length - limit : 0,
          )
        : candidates;
  } else {
    data = limit > 0
        ? sortedBundles.sublist(0, limit > total ? total : limit)
        : List.from(sortedBundles);
  }

  final startIndex = data.isNotEmpty
      ? sortedBundles.indexWhere((b) => b.id == data.first.id)
      : cursor?.after != null
      ? total
      : 0;
  final pagination = calculatePagination(
    total,
    limit: limit,
    offset: startIndex,
  );
  final nextCursor = data.isNotEmpty && startIndex + data.length < total
      ? data.last.id
      : null;
  final previousCursor = data.isNotEmpty && startIndex > 0
      ? data.first.id
      : null;

  String? effectiveNextCursor = nextCursor;
  String? effectivePreviousCursor = previousCursor;

  // Edge case: empty result after cursor → preserve the cursor for navigation
  if (data.isEmpty && cursor?.after != null) {
    effectivePreviousCursor = cursor!.after;
  }
  if (data.isEmpty && cursor?.before != null) {
    effectiveNextCursor = cursor!.before;
  }

  return Paginated(
    data: data,
    pagination: PaginationInfo(
      total: pagination.total,
      hasNextPage: pagination.hasNextPage,
      hasPreviousPage: pagination.hasPreviousPage,
      currentPage: pagination.currentPage,
      totalPages: pagination.totalPages,
      nextCursor: effectiveNextCursor,
      previousCursor: effectivePreviousCursor,
    ),
  );
}
