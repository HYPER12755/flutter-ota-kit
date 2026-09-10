/// Spawns the PocketBase binary as a child process, capturing its stdout/stderr
/// and providing clean start/stop semantics.
///
/// PB reads its data directory from the `--dir` flag (default `./pb_data`).
/// The CLI's installer pre-creates that directory and copies hooks into
/// `pb_data/pb_hooks/` before the first start.
///
/// A PID file (`pb.pid`) is written to the data directory on start so that
/// `stop` can find and terminate the process even after the CLI restarts.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class PocketBaseProcess {
  PocketBaseProcess._(this.process, this.dataDir, this.binaryPath)
    : _exitCodeCompleted = false {
    process.exitCode.then((_) => _exitCodeCompleted = true);
  }

  final Process process;
  final Directory dataDir;
  final File binaryPath;
  bool _exitCodeCompleted;

  bool get isRunning => !_exitCodeCompleted;

  int get pid => process.pid;

  Future<int> get exitCode => process.exitCode;

  Stream<List<int>> get output => process.stdout;
  Stream<List<int>> get errors => process.stderr;

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

  File get pidFile => File(p.join(dataDir.path, 'pb.pid'));
  File get configFile => File(p.join(dataDir.path, 'pb.json'));

  /// Read the stored PID from the PID file, or -1 if not present.
  int readPid() {
    if (!pidFile.existsSync()) return -1;
    final content = pidFile.readAsStringSync().trim();
    return int.tryParse(content) ?? -1;
  }

  /// Check if the process identified by the PID file is still alive.
  Future<bool> isRunningByPidFile() async {
    final pid = readPid();
    if (pid <= 0) return false;
    try {
      final result = await Process.run('kill', ['-0', '$pid']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  void _writePidFile(int pid) {
    pidFile.writeAsStringSync(pid.toString());
  }

  void _writeConfigFile(int pid) {
    configFile.writeAsStringSync(
      jsonEncode({
        'pid': pid,
        'host': host,
        'port': port,
        'url': 'http://$host:$port',
      }),
    );
  }

  Map<String, dynamic>? readConfig() {
    if (!configFile.existsSync()) return null;
    try {
      return jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void deletePidFile() {
    if (pidFile.existsSync()) pidFile.deleteSync();
    if (configFile.existsSync()) configFile.deleteSync();
  }

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

    final mergedEnv = <String, String>{...Platform.environment, ...?env};

    // Create superuser if credentials provided (PB 0.40+ doesn't support
    // PB_ADMIN_EMAIL env var, so we use the CLI directly).
    if (adminEmail != null && adminPassword != null) {
      final result = await Process.run(binaryPath.path, [
        'superuser',
        'upsert',
        '--dir=${dataDir.path}',
        adminEmail,
        adminPassword,
      ], environment: mergedEnv);
      if (result.exitCode != 0) {
        // Non-fatal; serve will continue but schema install may fail.
      }
    }

    final proc = await Process.start(
      binaryPath.path,
      ['serve', '--http=${host}:$port', '--dir=${dataDir.path}'],
      environment: mergedEnv,
      mode: ProcessStartMode.detached,
    );

    _writePidFile(proc.pid);
    _writeConfigFile(proc.pid);

    // Wait for the health endpoint to come up.
    final deadline = DateTime.now().add(readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 250),
        );
        socket.destroy();
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    _process = PocketBaseProcess._(proc, dataDir, binaryPath);
    return _process!;
  }

  /// Stop the running process by sending SIGINT, then SIGKILL if needed.
  /// Also cleans up the PID file.
  Future<void> stop() async {
    final proc = _process;
    if (proc != null) {
      await proc.stop();
      _process = null;
    } else {
      // Try stopping by PID file (for externally started processes).
      final pid = readPid();
      if (pid > 0) {
        try {
          Process.killPid(pid, ProcessSignal.sigint);
          // Give it a moment to shut down gracefully.
          await Future<void>.delayed(const Duration(seconds: 2));
          // Force kill if still alive.
          try {
            final check = await Process.run('kill', ['-0', '$pid']);
            if (check.exitCode == 0) {
              Process.killPid(pid, ProcessSignal.sigkill);
            }
          } catch (_) {}
        } catch (_) {}
      }
    }
    deletePidFile();
  }

  /// Get combined stdout+stderr log lines from the running process.
  Stream<String> get logStream async* {
    final proc = _process;
    if (proc == null) return;
    yield* proc.output
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) => '[stdout] $line');
    yield* proc.errors
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) => '[stderr] $line');
  }
}
