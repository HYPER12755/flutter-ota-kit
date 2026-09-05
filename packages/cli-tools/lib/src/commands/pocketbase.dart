/// `flutter_ota_kit pocketbase` — manage a local PocketBase instance.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../cli_base.dart';
import '../pocketbase/data_bootstrap.dart';
import '../pocketbase/installer.dart';
import '../pocketbase/process_manager.dart';
import '../pocketbase/schema_installer.dart';
import '../ui/ui.dart';

class PocketBaseCommand extends FlutterPatcherCommand {
  PocketBaseCommand() {
    addSubcommand(PocketBaseInstallCommand());
    addSubcommand(PocketBaseServeCommand());
    addSubcommand(PocketBaseStopCommand());
    addSubcommand(PocketBaseStatusCommand());
  }

  @override
  String get name => 'pocketbase';

  @override
  String get description =>
      'Manage a local PocketBase instance (install / serve / stop / status).';

  @override
  ArgParser get argParser => ArgParser();

  @override
  Future<int> run() => runGuarded(() async {
    err('Missing subcommand. Use: install | serve | stop | status');
    return;
  });
}

class PocketBaseInstallCommand extends FlutterPatcherCommand {
  @override
  String get name => 'install';

  @override
  String get description => 'Download + extract the PocketBase binary.';

  @override
  ArgParser get argParser =>
      ArgParser()..addOption('version', help: 'PocketBase version to install.');

  @override
  Future<int> run() => runGuarded(() async {
    final version =
        argResults!['version'] as String? ?? kDefaultPocketBaseVersion;
    final installer = PocketBaseInstaller(version: version);
    final paths = installer.paths();
    step('Installing PocketBase v$version to ${paths.installDir.path}...');
    final result = await installer.ensureInstalled(
      paths: paths,
      onProgress: (p) {
        stdout.write('\r  ${(p * 100).toStringAsFixed(0)}%   ');
      },
    );
    stdout.writeln();
    if (result.alreadyInstalled) {
      step('Already installed at ${paths.binaryPath.path}');
    } else {
      step(
        'Downloaded ${(result.bytesDownloaded / 1024 / 1024).toStringAsFixed(1)} MB',
      );
      step('Binary ready at ${paths.binaryPath.path}');
    }
    return;
  });
}

class PocketBaseServeCommand extends FlutterPatcherCommand {
  @override
  String get name => 'serve';

  @override
  String get description =>
      'Start a local PocketBase + install the flutter_ota_kit schema.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('version', help: 'PocketBase version.')
    ..addOption('port', help: 'PB HTTP port.', defaultsTo: '8090')
    ..addOption('host', help: 'PB bind address.', defaultsTo: '127.0.0.1')
    ..addOption('data-dir', help: 'PB data directory.')
    ..addOption('admin-email', help: 'Bootstrap admin email.')
    ..addOption('admin-password', help: 'Bootstrap admin password.')
    ..addFlag(
      'install-hooks',
      help: 'Copy bundled JS hooks into the data dir on start.',
      defaultsTo: true,
    );

  @override
  Future<int> run() => runGuarded(() async {
    final r = argResults!;
    final version = r['version'] as String? ?? kDefaultPocketBaseVersion;
    final port = int.tryParse(r['port'] as String? ?? '8090') ?? 8090;
    final host = r['host'] as String? ?? '127.0.0.1';
    final dataDirOverride = r['data-dir'] as String?;
    final adminEmail =
        r['admin-email'] as String? ??
        Platform.environment['POCKETBASE_ADMIN_EMAIL'];
    final adminPassword =
        r['admin-password'] as String? ??
        Platform.environment['POCKETBASE_ADMIN_PASSWORD'];
    final installHooks = r['install-hooks'] as bool? ?? true;

    final paths = PocketBaseInstallPaths.resolve(version: version);
    final dataDir = dataDirOverride != null
        ? Directory(dataDirOverride)
        : paths.installDir;
    final installer = PocketBaseInstaller(version: version);
    step('Ensuring PocketBase v$version is installed...');
    await installer.ensureInstalled(paths: paths);
    step('Binary at ${paths.binaryPath.path}');

    if (installHooks) {
      final bootstrap = PocketBaseDataBootstrap(
        dataDir: dataDir,
        hooksSourceDir: _hooksSourceDir(),
      );
      final installed = await bootstrap.install();
      if (installed.isNotEmpty) {
        step('Installed hooks: ${installed.join(', ')}');
      }
    }

    final manager = PocketBaseProcessManager(
      binaryPath: paths.binaryPath,
      dataDir: dataDir,
      port: port,
      host: host,
    );
    step(
      'Starting PocketBase on http://$host:$port (data: ${dataDir.path})...',
    );
    await manager.start(adminEmail: adminEmail, adminPassword: adminPassword);
    step('PocketBase is running (pid ${manager.process!.pid}).');

    if (adminEmail != null && adminPassword != null) {
      step('Installing flutter_ota_kit schema...');
      final schemaInstaller = PocketBaseSchemaInstaller(
        url: 'http://$host:$port',
        adminEmail: adminEmail,
        adminPassword: adminPassword,
      );
      try {
        final res = await schemaInstaller.install();
        if (res.created.isNotEmpty) {
          step('Created collections: ${res.created.join(', ')}');
        }
        if (res.skipped.isNotEmpty) {
          step('Already present: ${res.skipped.join(', ')}');
        }
      } catch (e) {
        warn('Schema install failed: $e');
      }
    } else {
      step('Skipping schema install (no --admin-email/--admin-password).');
    }

    banner('pocketbase');
    box('flutter_ota_kit pocketbase serve', [
      'Local PocketBase is running:',
      '',
      kv('url', 'http://$host:$port'),
      kv('admin-ui', 'http://$host:$port/_/'),
      kv('data', dataDir.path),
      kv('pid', '${manager.process!.pid}'),
    ]);

    // Wait for SIGINT/SIGTERM.
    final done = Completer<void>();
    ProcessSignal.sigint.watch().listen((_) => done.complete());
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) => done.complete());
    }
    await done.future;
    step('Shutting down PocketBase...');
    await manager.stop();
    step('PocketBase stopped.');
    return;
  });

  static Directory _hooksSourceDir() {
    final exe = Platform.script.toFilePath();
    final pkgRoot = Directory(p.dirname(p.dirname(p.dirname(exe))));
    return Directory(p.join(pkgRoot.path, 'lib', 'src', 'pocketbase', 'hooks'));
  }
}

class PocketBaseStopCommand extends FlutterPatcherCommand {
  @override
  String get name => 'stop';

  @override
  String get description =>
      'Hint to stop a running PocketBase (Ctrl+C in serve).';

  @override
  Future<int> run() => runGuarded(() async {
    step('Use Ctrl+C on the running serve process to stop PocketBase.');
    return;
  });
}

class PocketBaseStatusCommand extends FlutterPatcherCommand {
  @override
  String get name => 'status';

  @override
  String get description => 'Show the installed PocketBase version + path.';

  @override
  Future<int> run() => runGuarded(() async {
    final paths = PocketBaseInstallPaths.resolve();
    final exists = await paths.binaryPath.exists();
    if (exists) {
      step(
        'PocketBase v${paths.version}: installed at ${paths.binaryPath.path}',
      );
    } else {
      step(
        'PocketBase: not installed. Run `flutter_ota_kit pocketbase install`.',
      );
    }
    return;
  });
}
