import 'package:flutter_patcher_plugin_core/src/bundle_unit_of_work.dart';
import 'package:flutter_patcher_plugin_core/src/bundle_unit_of_work_store.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    clearUnitOfWorkStore();
  });

  group('isUnitOfWorkContext', () {
    test('returns true for Map<String, Object?>', () {
      expect(isUnitOfWorkContext(<String, Object?>{}), isTrue);
    });

    test('returns false for null', () {
      expect(isUnitOfWorkContext(null), isFalse);
    });

    test('returns false for non-map', () {
      expect(isUnitOfWorkContext('string'), isFalse);
      expect(isUnitOfWorkContext(42), isFalse);
    });

    test('returns false for wrong map type', () {
      // Dart generics are covariant, so Map<String, int> IS Map<String, Object?>
      // Only key-type mismatches fail the check
      expect(isUnitOfWorkContext(<int, Object?>{}), isFalse);
      expect(isUnitOfWorkContext(<int, String>{}), isFalse);
    });
  });

  group('getRequestBundleUnitOfWork', () {
    test('returns null for null context', () {
      expect(getRequestBundleUnitOfWork(null), isNull);
    });

    test('returns null for invalid context', () {
      expect(getRequestBundleUnitOfWork('not a map'), isNull);
    });

    test('creates new UoW for valid context', () {
      final context = <String, Object?>{};
      final uow1 = getRequestBundleUnitOfWork(context);
      expect(uow1, isA<BundleUnitOfWork>());
    });

    test('returns same UoW for same context (identity)', () {
      final context = <String, Object?>{};
      final uow1 = getRequestBundleUnitOfWork(context);
      final uow2 = getRequestBundleUnitOfWork(context);
      expect(identical(uow1, uow2), isTrue);
    });

    test('returns different UoW for different contexts', () {
      final ctx1 = <String, Object?>{};
      final ctx2 = <String, Object?>{};
      final uow1 = getRequestBundleUnitOfWork(ctx1);
      final uow2 = getRequestBundleUnitOfWork(ctx2);
      expect(identical(uow1, uow2), isFalse);
    });
  });

  group('clearUnitOfWorkStore', () {
    test('removes all entries', () {
      final ctx = <String, Object?>{};
      final uow = getRequestBundleUnitOfWork(ctx);
      expect(uow, isNotNull);
      clearUnitOfWorkStore();
      // After clearing, a new UoW should be created for the same context
      final uow2 = getRequestBundleUnitOfWork(ctx);
      expect(identical(uow, uow2), isFalse);
    });
  });
}
