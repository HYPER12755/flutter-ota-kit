/// Spawns the PocketBase binary as a child process, capturing its stdout/stderr
/// and providing clean start/stop semantics.
///
/// PB reads its data directory from the `--dir` flag (default `./pb_data`).
/// The CLI's installer pre-creates that directory and copies hooks into
/// `pb_data/pb_hooks/` before the first start.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

class PocketBaseProcess {
  PocketBaseProcess._(
    this.process,
    this.dataDir,
    this.binaryPath,
  );

  final Process process;
  final Directory dataDir;
  final File binaryPath;

  bool get isRunning => true; // Process instance is always present after start.

  int get pid => process.pid;

  Future<int> get exitCode => process.exitCode;

  /// Returns the stdout/stderr streams merged.
  Stream<List<int>> get output => process.stdout;
  Stream<List<int>> get errors => process.stderr;

  /// Send SIGINT (Ctrl+C) for a graceful shutdown, then SIGKILL if needed.
  Future<void> stop({Duration timeout = const Duration(seconds: 5)}) async {
    if (Platform.isWindows) {
      process.kill();
    } else {
      process.kill(ProcessSignal.sigint);
    }
    try {
      await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
  }
}

class PocketBaseProcessManager {
  PocketBaseProcessManager({
    required this.binaryPath,
    required this.dataDir,
    this.port = 8090,
    this.host = '127.0.0.1',
  });

  final File binaryPath;
  final Directory dataDir;
  final int port;
  final String host;

  PocketBaseProcess? _process;
  PocketBaseProcess? get process => _process;

  /// Start PB in the background. Returns once PB is listening (or after a
  /// short timeout waiting for it to come up).
  Future<PocketBaseProcess> start({
    Map<String, String>? env,
    String? adminEmail,
    String? adminPassword,
    Duration readyTimeout = const Duration(seconds: 15),
  }) async {
    if (_process != null) {
      throw StateError('PocketBase is already running (pid ${_process!.pid})');
    }
    if (!await binaryPath.exists()) {
      throw StateError(
        'PocketBase binary not found at ${binaryPath.path}. '
        'Run `flutter_ota_kit pocketbase install` first.',
      );
    }
    await dataDir.create(recursive: true);
    final hooksDir = Directory(p.join(dataDir.path, 'pb_hooks'));
    await hooksDir.create(recursive: true);

    final mergedEnv = <String, String>{
      ...Platform.environment,
      if (adminEmail != null) 'PB_ADMIN_EMAIL': adminEmail,
      if (adminPassword != null) 'PB_ADMIN_PASSWORD': adminPassword,
      ...?env,
    };

    final proc = await Process.start(
      binaryPath.path,
      ['serve', '--http=${host}:$port', '--dir=${dataDir.path}'],
      environment: mergedEnv,
      mode: ProcessStartMode.detached,
    );

    // Wait for the health endpoint to come up (best-effort; fall through
    // after readyTimeout either way).
    final deadline = DateTime.now().add(readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await Socket.connect(host, port,
            timeout: const Duration(milliseconds: 250));
        socket.destroy();
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    _process = PocketBaseProcess._(proc, dataDir, binaryPath);
    return _process!;
  }

  Future<void> stop() async {
    final proc = _process;
    if (proc == null) return;
    await proc.stop();
    _process = null;
  }
}
