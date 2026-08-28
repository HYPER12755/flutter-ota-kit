/// Check whether a value is a plain Dart Map (not a List, not a class instance
/// with a different runtimeType).
///
/// Faithful port of hot-updater `isObject.ts`.
bool isObject(Object? value) => value is Map<String, Object?>;
