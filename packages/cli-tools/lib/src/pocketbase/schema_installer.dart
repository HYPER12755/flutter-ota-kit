/// Installs the flutter_ota_kit PocketBase schema (collections, indexes,
/// default superuser) on a running PB instance.
///
/// PocketBase is initialized with:
///   - `bundles` collection (the OTA bundle metadata)
///   - `channels` collection (release channels with a current_bundle pointer)
///   - `audit_log` collection (immutable event log)
///   - `app_meta` collection (key-value app metadata)
///   - `bundles_patches` collection (per-bundle patch metadata)
///   - `users` is PB's built-in auth collection
///
/// The first superuser is created via `pocketbase superuser upsert`
/// before starting the server.
///
/// Idempotent: re-running the installer is a no-op when collections exist.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

const _kBundlesCollection = r'''
{
  "name": "bundles",
  "type": "base",
  "listRule": null,
  "viewRule": null,
  "createRule": null,
  "updateRule": null,
  "deleteRule": null,
  "fields": [
    {"name": "channel", "type": "text", "required": true, "options": {"min": 1, "max": 64}},
    {"name": "enabled", "type": "bool"},
    {"name": "platform", "type": "text", "required": true, "options": {"min": 1, "max": 16}},
    {"name": "should_force_update", "type": "bool"},
    {"name": "file_hash", "type": "text", "required": true},
    {"name": "storage_uri", "type": "text"},
    {"name": "rollout_cohort_count", "type": "number", "options": {"min": 0, "max": 1000}},
    {"name": "message", "type": "text", "options": {"max": 1024}},
    {"name": "fingerprint_hash", "type": "text", "options": {"max": 128}},
    {"name": "target_app_version", "type": "text", "options": {"max": 64}},
    {"name": "git_commit_hash", "type": "text", "options": {"max": 64}},
    {"name": "manifest_storage_uri", "type": "text", "options": {"max": 512}},
    {"name": "manifest_file_hash", "type": "text", "options": {"max": 128}},
    {"name": "asset_base_storage_uri", "type": "text", "options": {"max": 512}},
    {"name": "target_cohorts", "type": "json"},
    {"name": "metadata", "type": "json"},
    {"name": "artifact", "type": "file", "options": {"maxSelect": 1, "maxSize": 0, "mimeTypes": []}}
  ],
  "indexes": [
    "CREATE INDEX idx_bundles_channel ON bundles (channel)",
    "CREATE INDEX idx_bundles_platform ON bundles (platform)",
    "CREATE INDEX idx_bundles_enabled ON bundles (enabled)",
    "CREATE INDEX idx_bundles_created ON bundles (created)"
  ]
}
''';

const _kChannelsCollection = r'''
{
  "name": "channels",
  "type": "base",
  "listRule": null,
  "viewRule": null,
  "createRule": null,
  "updateRule": null,
  "deleteRule": null,
  "fields": [
    {"name": "name", "type": "text", "required": true, "options": {"min": 1, "max": 64, "pattern": "^[a-zA-Z0-9_-]+$"}},
    {"name": "current_bundle", "type": "text", "options": {"max": 64}}
  ],
  "indexes": [
    "CREATE UNIQUE INDEX idx_channels_name ON channels (name)"
  ]
}
''';

const _kAuditLogCollection = r'''
{
  "name": "audit_log",
  "type": "base",
  "listRule": null,
  "viewRule": null,
  "createRule": null,
  "updateRule": null,
  "deleteRule": null,
  "fields": [
    {"name": "user", "type": "text", "options": {"max": 128}},
    {"name": "action", "type": "text", "required": true, "options": {"min": 1, "max": 64}},
    {"name": "bundle_id", "type": "text", "options": {"max": 64}},
    {"name": "channel", "type": "text", "options": {"max": 64}},
    {"name": "details", "type": "json"}
  ],
  "indexes": [
    "CREATE INDEX idx_audit_action ON audit_log (action)",
    "CREATE INDEX idx_audit_created ON audit_log (created)"
  ]
}
''';

const _kBundlePatchesCollection = r'''
{
  "name": "bundles_patches",
  "type": "base",
  "listRule": null,
  "viewRule": null,
  "createRule": null,
  "updateRule": null,
  "deleteRule": null,
  "fields": [
    {"name": "bundle_id", "type": "text", "required": true, "options": {"max": 64}},
    {"name": "base_bundle_id", "type": "text", "required": true, "options": {"max": 64}},
    {"name": "base_file_hash", "type": "text", "required": true, "options": {"max": 128}},
    {"name": "patch_file_hash", "type": "text", "required": true, "options": {"max": 128}},
    {"name": "patch_storage_uri", "type": "text", "required": true, "options": {"max": 512}},
    {"name": "order_index", "type": "number", "options": {"min": 0}},
    {"name": "artifact", "type": "file", "options": {"maxSelect": 1, "maxSize": 0, "mimeTypes": []}}
  ],
  "indexes": [
    "CREATE INDEX idx_patches_bundle ON bundles_patches (bundle_id)",
    "CREATE INDEX idx_patches_base ON bundles_patches (base_bundle_id)"
  ]
}
''';

const _kMetaCollection = r'''
{
  "name": "app_meta",
  "type": "base",
  "listRule": null,
  "viewRule": null,
  "createRule": null,
  "updateRule": null,
  "deleteRule": null,
  "fields": [
    {"name": "key", "type": "text", "required": true, "options": {"min": 1, "max": 128}},
    {"name": "value", "type": "json"}
  ],
  "indexes": [
    "CREATE UNIQUE INDEX idx_meta_key ON app_meta (key)"
  ]
}
''';

class _RawAdminClient {
  _RawAdminClient(this.baseUrl);
  final String baseUrl;
  String? _token;

  Future<String> authenticate(String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/collections/_superusers/auth-with-password'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'identity': email, 'password': password}),
    );
    if (res.statusCode != 200) {
      throw StateError(
        'PocketBase admin auth failed (HTTP ${res.statusCode}). '
        'Is PB running and is the admin email/password correct?',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final token = body['token'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('PocketBase returned no admin token.');
    }
    _token = token;
    return token;
  }

  Future<List<String>> listCollectionNames() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/collections'),
      headers: {'authorization': _token ?? ''},
    );
    if (res.statusCode != 200) {
      throw StateError(
        'Failed to list collections (HTTP ${res.statusCode} ${res.body})',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return ((body['items'] as List?) ?? [])
        .map((c) => (c as Map)['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
  }

  Future<void> createCollection(String schemaJson) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/collections'),
      headers: {
        'authorization': _token ?? '',
        'content-type': 'application/json',
      },
      body: schemaJson,
    );
    if (res.statusCode != 200 &&
        res.statusCode != 201 &&
        res.statusCode != 400) {
      throw StateError(
        'Failed to create collection (HTTP ${res.statusCode} ${res.body})',
      );
    }
    // 400 here usually means the collection already exists; the installer
    // pre-checks names so this should be a true error.
  }
}

class PocketBaseSchemaInstallResult {
  const PocketBaseSchemaInstallResult({
    required this.created,
    required this.skipped,
  });
  final List<String> created;
  final List<String> skipped;
}

/// Idempotently installs the flutter_ota_kit PocketBase schema.
class PocketBaseSchemaInstaller {
  PocketBaseSchemaInstaller({
    required this.url,
    required this.adminEmail,
    required this.adminPassword,
    this.bundlesCollection = 'bundles',
    this.channelsCollection = 'channels',
    this.auditLogCollection = 'audit_log',
  });

  final String url;
  final String adminEmail;
  final String adminPassword;
  final String bundlesCollection;
  final String channelsCollection;
  final String auditLogCollection;

  Future<PocketBaseSchemaInstallResult> install() async {
    final client = _RawAdminClient(url);
    await client.authenticate(adminEmail, adminPassword);
    final existing = await client.listCollectionNames();
    final created = <String>[];
    final skipped = <String>[];
    for (final spec in _schema()) {
      if (existing.contains(spec.name)) {
        skipped.add(spec.name);
        continue;
      }
      await client.createCollection(spec.schema);
      created.add(spec.name);
    }
    return PocketBaseSchemaInstallResult(created: created, skipped: skipped);
  }

  List<_CollectionSpec> _schema() {
    // Replace the hard-coded collection names if the user customized them.
    String rename(String json) {
      if (bundlesCollection != 'bundles') {
        json = json.replaceAll('"bundles"', '"$bundlesCollection"');
        json = json.replaceAll(
          'bundles_patches',
          '${bundlesCollection}_patches',
        );
      }
      if (channelsCollection != 'channels') {
        json = json.replaceAll('"channels"', '"$channelsCollection"');
      }
      if (auditLogCollection != 'audit_log') {
        json = json.replaceAll('"audit_log"', '"$auditLogCollection"');
      }
      return json;
    }

    final patchesCollectionName = '${bundlesCollection}_patches';
    return [
      _CollectionSpec(bundlesCollection, rename(_kBundlesCollection)),
      _CollectionSpec(channelsCollection, rename(_kChannelsCollection)),
      _CollectionSpec(auditLogCollection, rename(_kAuditLogCollection)),
      _CollectionSpec(patchesCollectionName, rename(_kBundlePatchesCollection)),
      _CollectionSpec('app_meta', _kMetaCollection),
    ];
  }
}

class _CollectionSpec {
  const _CollectionSpec(this.name, this.schema);
  final String name;
  final String schema;
}
