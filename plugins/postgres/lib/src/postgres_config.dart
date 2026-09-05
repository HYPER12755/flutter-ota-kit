import 'package:postgres/postgres.dart';

import 'postgres_client.dart';

/// Connection configuration for the Postgres backend.
///
/// Faithful port of hot-updater `PostgresConfig extends PoolConfig` (the `pg`
/// connection options). Mirrors the Supabase plugin's `clientFactory` seam:
/// when [clientFactory] is provided, the plugin uses the injected client instead
/// of opening a real connection — this is what makes the plugin unit-testable
/// without a live database.
class PostgresConfig {
  const PostgresConfig({
    required this.host,
    this.port = 5432,
    required this.database,
    this.username,
    this.password,
    this.sslMode,
    this.clientFactory,
  });

  final String host;
  final int port;
  final String database;
  final String? username;
  final String? password;
  final SslMode? sslMode;

  /// Optional factory for injecting a [PostgresClientLike] (tests / custom pools).
  final PostgresClientFactory? clientFactory;
}

/// Builds a [PostgresClientLike] from a [PostgresConfig].
typedef PostgresClientFactory = PostgresClientLike Function(
  PostgresConfig config,
);
