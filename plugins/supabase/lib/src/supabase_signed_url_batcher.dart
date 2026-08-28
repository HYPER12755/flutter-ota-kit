/// Faithful port of hot-updater `plugins/supabase/src/supabaseSignedUrlBatcher.ts`.
library;

import 'dart:async';

import 'supabase_client_adapter.dart';

/// A pending signed URL request waiting for the next flush.
class _PendingSignedUrl {
  final String key;
  final void Function(Object error) reject;
  final void Function(String signedUrl) resolve;

  _PendingSignedUrl({
    required this.key,
    required this.reject,
    required this.resolve,
  });
}

/// Extract a human-readable message from an unknown error value.
String _getErrorMessage(Object? error) {
  if (error is Error) return error.toString();
  if (error is Exception) return error.toString();
  if (error is Map && error['message'] is String) {
    return error['message'] as String;
  }
  return error.toString();
}

/// Signature of the batch signed URL generator. Returns the same shape as the
/// Supabase storage `createSignedUrls` call: a list of results aligned to the
/// input key order.
typedef CreateSignedUrls = Future<SupabaseSignedUrlListResult> Function(
  String bucketName,
  List<String> keys,
  int expiresIn,
);

/// Creates a function that batches signed URL generation requests per
/// bucket and flushes them on the next microtask, mirroring Supabase's
/// `createSignedUrls` batch API.
///
/// [createSignedUrls] must take a bucket name, list of keys, and expiry,
/// and return a [SupabaseSignedUrlListResult] whose `data` entries are aligned
/// to the input key order.
/// [formatObjectPath] builds the human-readable object path used in errors.
ResolveSignedUrl createSupabaseSignedUrlBatcher({
  required CreateSignedUrls createSignedUrls,
  required int expiresIn,
  required String Function(String bucketName, String key) formatObjectPath,
}) {
  var pendingByBucket = <String, List<_PendingSignedUrl>>{};
  var flushScheduled = false;

  Object createSignedUrlError(
    String bucketName,
    String key,
    Object error,
  ) =>
      StateError(
        'Failed to generate download URL for '
        '"${formatObjectPath(bucketName, key)}": ${_getErrorMessage(error)}',
      );

  Future<void> flush() async {
    final batches = pendingByBucket;
    pendingByBucket = <String, List<_PendingSignedUrl>>{};
    flushScheduled = false;

    await Future.wait(
      batches.entries.map((entry) async {
        final bucketName = entry.key;
        final pending = entry.value;

        try {
          final result = await createSignedUrls(
            bucketName,
            pending.map((p) => p.key).toList(),
            expiresIn,
          );

          final data = result.data;
          if (result.error != null || data == null) {
            final batchError =
                result.error ?? StateError('missing signed URL response');
            for (final request in pending) {
              request.reject(
                createSignedUrlError(bucketName, request.key, batchError),
              );
            }
            return;
          }

          for (var i = 0; i < pending.length; i++) {
            final request = pending[i];
            final row = data[i];
            if (row.error == null && row.signedUrl != null) {
              request.resolve(row.signedUrl!);
            } else {
              request.reject(
                createSignedUrlError(
                  bucketName,
                  request.key,
                  row.error ?? StateError('missing signed URL'),
                ),
              );
            }
          }
        } catch (error) {
          for (final request in pending) {
            request.reject(createSignedUrlError(bucketName, request.key, error));
          }
        }
      }),
    );
  }

  return (String bucketName, String key) {
    final completer = Completer<String>();
    final pending =
        pendingByBucket[bucketName] ?? <_PendingSignedUrl>[];
    pending.add(
      _PendingSignedUrl(
        key: key,
        reject: completer.completeError,
        resolve: completer.complete,
      ),
    );
    pendingByBucket[bucketName] = pending;

    if (!flushScheduled) {
      flushScheduled = true;
      Future.microtask(() => flush());
    }

    return completer.future;
  };
}

/// Resolved function returned by [createSupabaseSignedUrlBatcher].
typedef ResolveSignedUrl = Future<String> Function(
  String bucketName,
  String key,
);
