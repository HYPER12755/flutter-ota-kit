import 'd1_client.dart' show D1Client, D1ClientLike;

/// Configuration for the Cloudflare D1 database plugin.
class D1DatabaseConfig {
  const D1DatabaseConfig({
    required this.databaseId,
    required this.accountId,
    required this.cloudflareApiToken,
    this.clientFactory,
  });

  /// Cloudflare D1 database ID.
  final String databaseId;

  /// Cloudflare account ID.
  final String accountId;

  /// Cloudflare API token with D1 read/write permissions.
  final String cloudflareApiToken;

  /// Optional factory used to inject a [D1ClientLike] in tests.
  final D1ClientFactory? clientFactory;
}

/// Builds a [D1ClientLike] for the given [D1DatabaseConfig].
typedef D1ClientFactory = D1ClientLike Function(D1DatabaseConfig config);

/// Resolves the client for a config, using the injected factory when present.
D1ClientLike resolveD1Client(D1DatabaseConfig config) =>
    config.clientFactory?.call(config) ?? D1Client(config);
