import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_patcher_core/flutter_patcher_core.dart';
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart';

import 'backend.dart';
import 'sign.dart';
import 'util.dart';

/// Options for [deployBundle].
class DeployOptions {
  const DeployOptions({
    required this.source,
    required this.channel,
    required this.platform,
    this.message,
    this.force = false,
    this.targetAppVersion,
    this.fingerprintHash,
    this.signingKeyBase64,
    this.gitCommitHash,
    this.bundleId,
    this.metadata,
  });

  final String source;
  final String channel;
  final String platform;
  final String? message;
  final bool force;
  final String? targetAppVersion;
  final String? fingerprintHash;
  final String? signingKeyBase64;
  final String? gitCommitHash;
  final String? bundleId;
  final BundleMetadata? metadata;
}

/// Options for [listBundles].
class ListOptions {
  const ListOptions({
    this.channel,
    this.platform,
    this.enabled,
    this.limit = 20,
  });

  final String? channel;
  final String? platform;
  final bool? enabled;
  final int limit;
}

/// Build the zip, upload it, and register a [Bundle] via the backend.
Future<Bundle> deployBundle(Backend backend, DeployOptions opts) async {
  if (opts.targetAppVersion != null && opts.fingerprintHash != null) {
    throw StateError(
      'Use only one of target-app-version / fingerprint-hash (DB CHECK).',
    );
  }
  // Resolve the artifact to upload. If the source is already a zip (e.g. the
  // `patch.zip` produced by `flutter_patcher build`/`pack`), upload it directly.
  // Otherwise, if the source directory contains a `patch.zip`, use that. As a
  // fallback, zip the source directory (for pre-built bundle layouts).
  final sourceFile = File(opts.source);
  final bool sourceIsFile = sourceFile.existsSync() && sourceFile.statSync().type == FileSystemEntityType.file;
  final String zipPath;
  final bool shouldDelete;
  if (sourceIsFile && opts.source.endsWith('.zip')) {
    zipPath = opts.source;
    shouldDelete = false;
  } else {
    final dir = Directory(opts.source);
    final packaged = File('${dir.path}/patch.zip');
    if (await packaged.exists()) {
      zipPath = packaged.path;
      shouldDelete = false;
    } else {
      zipPath = await zipDirectory(opts.source);
      shouldDelete = true;
    }
  }

  try {
    final zipBytes = await File(zipPath).readAsBytes();
    // Device SDK verifies the artifact against an MD5 hex of the whole file,
    // so `fileHash` is always the MD5 hex (never a `sig:`-prefixed value).
    final md5Hex = md5.convert(zipBytes).toString();
    final signature = opts.signingKeyBase64 != null
        ? await ed25519Sign(utf8.encode(md5Hex), opts.signingKeyBase64!)
        : null;

    final bundleId = opts.bundleId ?? uuidV7();
    final key = backend.storageKeyFor(bundleId, 'patch.zip');
    final uploaded = await backend.storage.upload(key, zipPath);
    final storageUri = uploaded['storageUri'];
    if (storageUri == null || storageUri.isEmpty) {
      throw StateError('Storage upload returned no storageUri.');
    }

    final bundle = Bundle(
      id: bundleId,
      platform: Platform.fromValue(opts.platform),
      shouldForceUpdate: opts.force,
      enabled: true,
      fileHash: md5Hex,
      storageUri: storageUri,
      channel: opts.channel,
      message: opts.message,
      gitCommitHash: opts.gitCommitHash,
      targetAppVersion: opts.targetAppVersion,
      fingerprintHash: opts.fingerprintHash,
      metadata:
          opts.metadata ?? (signature != null ? BundleMetadata(signature: signature) : null),
      rolloutCohortCount: defaultRolloutCohortCount,
    );

    await backend.db.appendBundle(bundle);
    await backend.db.commitBundle();
    return bundle;
  } finally {
    if (shouldDelete) {
      try {
        await File(zipPath).delete();
      } catch (_) {
        // best effort cleanup.
      }
    }
  }
}

/// List bundles, filtered by the supplied options.
Future<Paginated<List<Bundle>>> listBundles(
  Backend backend,
  ListOptions opts,
) async {
  return backend.db.getBundles(
    DatabaseBundleQueryOptions(
      where: DatabaseBundleQueryWhere(
        channel: opts.channel,
        platform: opts.platform != null ? Platform.fromValue(opts.platform!) : null,
        enabled: opts.enabled,
      ),
      limit: opts.limit,
      orderBy: const DatabaseBundleQueryOrder(direction: 'desc'),
    ),
  );
}

/// Delete a bundle by id.
Future<void> deleteBundle(Backend backend, String id) async {
  final existing = await backend.db.getBundleById(id);
  if (existing == null) {
    throw StateError('Bundle "$id" not found.');
  }
  await backend.db.deleteBundle(existing);
  await backend.db.commitBundle();
}

/// Promote a bundle to a channel (enable + assign channel).
Future<void> promoteBundle(
  Backend backend,
  String id,
  String channel,
) async {
  final existing = await backend.db.getBundleById(id);
  if (existing == null) {
    throw StateError('Bundle "$id" not found.');
  }
  await backend.db.updateBundle(id, {'enabled': true, 'channel': channel});
  await backend.db.commitBundle();
}

/// Disable the latest enabled bundle on a channel (rollback).
///
/// Returns the id of the bundle that was disabled.
Future<String> rollbackChannel(Backend backend, String channel) async {
  final res = await backend.db.getBundles(
    DatabaseBundleQueryOptions(
      where: DatabaseBundleQueryWhere(channel: channel, enabled: true),
      limit: 1,
      orderBy: const DatabaseBundleQueryOrder(direction: 'desc'),
    ),
  );
  if (res.data.isEmpty) {
    throw StateError('No enabled bundle on channel "$channel" to roll back.');
  }
  final target = res.data.first;
  await backend.db.updateBundle(target.id, {'enabled': false});
  await backend.db.commitBundle();
  return target.id;
}

/// List channels configured on the backend.
Future<List<String>> listChannels(Backend backend) => backend.db.getChannels();

/// Return the currently enabled (live) bundle for a channel, if any.
Future<Bundle?> getChannel(Backend backend, String channel) async {
  final res = await listBundles(
    backend,
    ListOptions(channel: channel, enabled: true, limit: 1),
  );
  return res.data.isEmpty ? null : res.data.first;
}
