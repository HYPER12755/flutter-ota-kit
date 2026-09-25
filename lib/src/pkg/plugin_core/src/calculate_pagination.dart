import 'types.dart';

/// Calculate pagination metadata from total count, limit, and offset.
///
/// Faithful port of hot-updater `calculatePagination.ts`.
PaginationInfo calculatePagination(
  int total, {
  required int limit,
  required int offset,
}) {
  if (total == 0) {
    return const PaginationInfo(
      total: 0,
      hasNextPage: false,
      hasPreviousPage: false,
      currentPage: 1,
      totalPages: 0,
    );
  }

  final currentPage = (offset / limit).floor() + 1;
  final totalPages = (total / limit).ceil();
  final hasNextPage = offset + limit < total;
  final hasPreviousPage = offset > 0;

  return PaginationInfo(
    total: total,
    hasNextPage: hasNextPage,
    hasPreviousPage: hasPreviousPage,
    currentPage: currentPage,
    totalPages: totalPages,
  );
}
