import 'package:postgres/postgres.dart';

import 'postgres_config.dart';

/// Minimal Postgres session contract used by the plugin.
///
/// Mirrors the surface the Dart port needs from `package:postgres`
/// (`Session`/`SessionExecutor`): parameterized `execute` returning column maps,
/// `runTx` for transactional `commitBundle`, and `close`.
///
/// A mock implementation backs the unit tests (see `test/mock_postgres_client.dart`).
abstract class PostgresClientLike {
  /// Runs [sql] with named [parameters] (e.g. `@id`) and returns rows as
  /// column-name → value maps.
  Future<List<Map<String, dynamic>>> execute(
    String sql,
    Map<String, dynamic> parameters,
  );

  /// Runs [fn] inside a transaction. The argument is a client bound to the
  /// transaction session (only `execute` is supported on it; nested
  /// transactions are not supported).
  Future<T> runTx<T>(Future<T> Function(PostgresClientLike tx) fn);

  /// Closes the underlying connection.
  Future<void> close();
}

/// Real [PostgresClientLike] backed by `package:postgres`.
///
/// The connection is opened lazily on first use (so `createDatabasePlugin`'s
/// synchronous `factory` can build this client without `await`).
class PostgresClient implements PostgresClientLike {
  PostgresClient._(this._config, this._session, this._executor);

  final PostgresConfig _config;
  Session? _session;
  SessionExecutor? _executor;

  /// Creates a client that will open a real connection on first use.
  factory PostgresClient.connect(PostgresConfig config) =>
      PostgresClient._(config, null, null);

  Future<Session> get _activeSession async {
    if (_session != null) return _session!;
    final endpoint = Endpoint(
      host: _config.host,
      port: _config.port,
      database: _config.database,
      username: _config.username,
      password: _config.password,
    );
    final connection = await Connection.open(
      endpoint,
      settings: ConnectionSettings(sslMode: _config.sslMode),
    );
    _session = connection;
    _executor = connection;
    return connection;
  }

  @override
  Future<List<Map<String, dynamic>>> execute(
    String sql,
    Map<String, dynamic> parameters,
  ) async {
    final session = await _activeSession;
    final result = await session.execute(sql, parameters: parameters);
    return result.map((row) => row.toColumnMap()).toList();
  }

  @override
  Future<T> runTx<T>(Future<T> Function(PostgresClientLike tx) fn) async {
    final executor = _executor;
    if (executor == null) {
      throw UnsupportedError('Nested transactions are not supported');
    }
    return executor.runTx((tx) => fn(PostgresClient._(_config, tx, null)));
  }

  @override
  Future<void> close() async {
    final executor = _executor;
    if (executor != null) {
      await executor.close();
      _session = null;
      _executor = null;
    }
  }
}
