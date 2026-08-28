import 'dart:convert' show jsonEncode;

import 'package:http/http.dart' as http;
import 'package:http/http.dart';

/// A factory that returns the [http.Client] used by standalone plugins.
///
/// Injectable so tests can supply a mock client.
typedef StandaloneClientFactory = Client Function();

/// Configuration for the standalone repository (the database half of the
/// self-hosted backend).
class StandaloneRepositoryConfig {
  const StandaloneRepositoryConfig({
    required this.baseUrl,
    this.commonHeaders,
    this.routes,
    this.clientFactory,
  });

  final String baseUrl;
  final Map<String, String>? commonHeaders;
  final StandaloneRepositoryRoutes? routes;
  final StandaloneClientFactory? clientFactory;
}

/// Overridable route templates for the repository REST contract.
class StandaloneRepositoryRoutes {
  const StandaloneRepositoryRoutes({
    this.create = '/api/bundles',
    this.list = '/api/bundles',
    this.channels = '/api/bundles/channels',
    this.retrieve = '/api/bundles/:id',
    this.update = '/api/bundles/:id',
    this.delete = '/api/bundles/:id',
  });

  final String create;
  final String list;
  final String channels;
  final String retrieve;
  final String update;
  final String delete;
}

/// Configuration for the standalone storage (the storage half of the
/// self-hosted backend).
class StandaloneStorageConfig {
  const StandaloneStorageConfig({
    required this.baseUrl,
    this.commonHeaders,
    this.routes,
    this.clientFactory,
  });

  final String baseUrl;
  final Map<String, String>? commonHeaders;
  final StandaloneStorageRoutes? routes;
  final StandaloneClientFactory? clientFactory;
}

/// Overridable route templates for the storage REST contract.
class StandaloneStorageRoutes {
  const StandaloneStorageRoutes({
    this.upload = '/api/upload',
    this.getDownloadUrl = '/api/getDownloadUrl',
    this.delete = '/api/delete',
    this.readText = '/api/readText',
    this.list = '/api/list',
    this.serveFile = '/api/_file',
  });

  final String upload;
  final String getDownloadUrl;
  final String delete;
  final String readText;
  final String list;
  final String serveFile;
}

/// Build a request path from a route template that may contain `:id`.
String buildPath(String template, {String? id}) {
  var path = template;
  if (id != null) path = path.replaceAll(':id', id);
  return path;
}

/// Join [baseUrl] and [path], ensuring exactly one `/` between them.
String joinUrl(String baseUrl, String path) {
  final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  final p = path.startsWith('/') ? path : '/$path';
  return '$base$p';
}

/// Merge [commonHeaders] with extra per-request headers.
Map<String, String> mergeHeaders(
  Map<String, String>? common,
  Map<String, String>? extra,
) {
  final result = <String, String>{};
  if (common != null) result.addAll(common);
  if (extra != null) result.addAll(extra);
  return result;
}

/// Envelope helper: standalone create expects `[bundle]`.
String encodeBundleList(Map<String, dynamic> bundle) => jsonEncode([bundle]);
