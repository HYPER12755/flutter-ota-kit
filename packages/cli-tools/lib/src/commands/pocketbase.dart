/// `flutter_ota_kit pocketbase` — manage a local PocketBase instance.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_ota_kit_pocketbase/flutter_ota_kit_pocketbase.dart';
import 'package:path/path.dart' as p;

import '../cli_base.dart';
import '../pack.dart';
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
    addSubcommand(PocketBaseBackupCommand());
    addSubcommand(PocketBaseExportCommand());
    addSubcommand(PocketBaseImportCommand());
    addSubcommand(PocketBaseAdminCommand());
    addSubcommand(PocketBaseMigrateCommand());
    addSubcommand(PocketBaseHealthCommand());
    addSubcommand(PocketBaseLogsCommand());
    addSubcommand(PocketBaseRecordsCommand());
    addSubcommand(PocketBaseCollectionsCommand());
    addSubcommand(PocketBaseSettingsCommand());
    addSubcommand(PocketBaseSqlCommand());
    addSubcommand(PocketBaseCronsCommand());
    addSubcommand(PocketBaseQueryCommand());
    addSubcommand(PocketBaseConfigCommand());
  }

  @override
  String get name => 'pocketbase';

  @override
  String get description =>
      'Manage a local PocketBase instance (install / serve / stop / '
      'status / backup / export / import / admin / migrate / health / '
      'logs / records / collections / settings / sql / crons / query / config).';
}

class PocketBaseInstallCommand extends FlutterPatcherCommand {
  PocketBaseInstallCommand() {
    argParser.addOption('version', help: 'PocketBase version to install.');
  }

  @override
  String get name => 'install';

  @override
  String get description => 'Download + extract the PocketBase binary.';

  @override
  Future<int> run() => runGuarded(() async {
    final version =
        argResults!['version'] as String? ?? kDefaultPocketBaseVersion;
    final installer = PocketBaseInstaller(version: version);
    final paths = installer.paths();
    banner('pocketbase · install');
    final bar = ProgressBar(1, 'Downloading PocketBase v$version');
    final result = await installer.ensureInstalled(
      paths: paths,
      onProgress: (p) {
        bar.update((p * 100).round());
      },
    );
    bar.close();
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
  PocketBaseServeCommand() {
    argParser.addOption('version', help: 'PocketBase version.');
    argParser.addOption('port', help: 'PB HTTP port.', defaultsTo: '8090');
    argParser.addOption(
      'host',
      help: 'PB bind address.',
      defaultsTo: '127.0.0.1',
    );
    argParser.addOption('data-dir', help: 'PB data directory.');
    argParser.addOption('admin-email', help: 'Bootstrap admin email.');
    argParser.addOption('admin-password', help: 'Bootstrap admin password.');
    argParser.addFlag(
      'install-hooks',
      help: 'Copy bundled JS hooks into the data dir on start.',
      defaultsTo: true,
    );
  }

  @override
  String get name => 'serve';

  @override
  String get description =>
      'Start a local PocketBase + install the flutter-ota schema.';

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

    // Wait for PB to be ready.
    for (var i = 0; i < 20; i++) {
      try {
        final hc = PocketBaseClient('http://$host:$port');
        final ok = await hc.health();
        hc.close();
        if (ok) break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    if (adminEmail != null && adminPassword != null) {
      step('Installing flutter-ota schema...');
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
    box('flutter-ota pocketbase serve', [
      'Local PocketBase is running:',
      '',
      kv('url', 'http://$host:$port'),
      kv('admin-ui', 'http://$host:$port/_/'),
      kv('data', dataDir.path),
      kv('pid', '${manager.process!.pid}'),
    ]);

    // Wait for SIGINT/SIGTERM.
    final done = Completer<void>();
    ProcessSignal.sigint.watch().listen((_) {
      if (!done.isCompleted) done.complete();
    });
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) {
        if (!done.isCompleted) done.complete();
      });
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
  PocketBaseStopCommand() {
    argParser.addOption('port', help: 'HTTP port.', defaultsTo: '8090');
    argParser.addOption('host', help: 'Bind address.', defaultsTo: '127.0.0.1');
  }

  @override
  String get name => 'stop';

  @override
  String get description => 'Stop a running PocketBase instance.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · stop');
    final port = int.tryParse(argResults!['port'] as String? ?? '8090') ?? 8090;
    final host = argResults!['host'] as String? ?? '127.0.0.1';
    final mgr = PocketBaseProcessManager(
      binaryPath: PocketBaseInstallPaths.resolve().binaryPath,
      dataDir: PocketBaseInstallPaths.resolve().installDir,
      port: port,
      host: host,
    );
    final pid = mgr.readPid();
    if (pid <= 0) {
      step('No PocketBase process found.');
      return;
    }
    step('Stopping PocketBase (PID $pid)...');
    await mgr.stop();
    step('PocketBase stopped.');
  });
}

class PocketBaseStatusCommand extends FlutterPatcherCommand {
  PocketBaseStatusCommand() {
    argParser.addOption('port', help: 'HTTP port.', defaultsTo: '8090');
    argParser.addOption('host', help: 'Bind address.', defaultsTo: '127.0.0.1');
  }

  @override
  String get name => 'status';

  @override
  String get description => 'Show installed version, PID, and health.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · status');
    final r = argResults!;
    final port = int.tryParse(r['port'] as String? ?? '8090') ?? 8090;
    final host = r['host'] as String? ?? '127.0.0.1';

    final paths = PocketBaseInstallPaths.resolve();
    final exists = await paths.binaryPath.exists();
    final manager = PocketBaseProcessManager(
      binaryPath: paths.binaryPath,
      dataDir: paths.installDir,
      port: port,
      host: host,
    );

    final pid = manager.readPid();
    final pidAlive = pid > 0 ? await manager.isRunningByPidFile() : false;

    var healthy = false;
    try {
      final client = PocketBaseClient('http://$host:$port');
      healthy = await client.health();
      client.close();
    } catch (_) {}

    box('status', [
      kv('version', paths.version),
      kv('binary', exists ? green('installed') : red('not installed')),
      kv(
        'pid',
        pidAlive ? green('$pid') : (pid > 0 ? yellow('$pid (dead)') : dim('-')),
      ),
      kv('health', healthy ? green('healthy') : red('unreachable')),
      kv('url', 'http://$host:$port'),
    ]);
  });
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

void _addBackendOptions(ArgParser parser) {
  parser.addOption('url', help: 'PocketBase URL (auto-detected if running).');
  parser.addOption('admin-email', help: 'Admin email.');
  parser.addOption('admin-password', help: 'Admin password.');
  parser.addOption('version', help: 'PocketBase version.');
  parser.addOption('data-dir', help: 'PB data directory.');
}

String _safeSubstring(String? s, int length) {
  if (s == null || s.isEmpty) return '';
  return s.length > length ? s.substring(0, length) : s;
}

(String url, String adminEmail, String adminPassword) _resolveBackend(
  ArgResults r,
) {
  final url = r['url'] as String? ?? _detectRunningUrl(r);
  if (url == null || url.isEmpty) {
    throw const PackException(
      'No PocketBase URL. Run `flutter-ota pocketbase serve` or pass --url.',
      64,
    );
  }
  final admin =
      r['admin-email'] as String? ??
      Platform.environment['POCKETBASE_ADMIN_EMAIL'] ??
      '';
  final pass =
      r['admin-password'] as String? ??
      Platform.environment['POCKETBASE_ADMIN_PASSWORD'] ??
      '';
  if (admin.isEmpty || pass.isEmpty) {
    throw const PackException(
      'Admin credentials required. Use --admin-email/--admin-password '
      'or set POCKETBASE_ADMIN_EMAIL/POCKETBASE_ADMIN_PASSWORD env vars.',
      64,
    );
  }
  return (url, admin, pass);
}

Future<PocketBaseClient> _getClient(ArgResults r) async {
  final (url, admin, pass) = _resolveBackend(r);
  final client = PocketBaseClient(url);
  await client.authenticate(admin, pass);
  return client;
}

String? _detectRunningUrl(ArgResults r) {
  final version = r['version'] as String? ?? kDefaultPocketBaseVersion;
  final dataDirOverride = r['data-dir'] as String?;
  final paths = PocketBaseInstallPaths.resolve(version: version);
  final dataDir = dataDirOverride != null
      ? Directory(dataDirOverride)
      : paths.installDir;
  final config = PocketBaseProcessManager(
    binaryPath: paths.binaryPath,
    dataDir: dataDir,
  ).readConfig();
  return config?['url'] as String?;
}

Future<T> _pbStep<T>(
  String label,
  Future<T> Function(PocketBaseClient client) fn,
  ArgResults r,
) async {
  final steps = Steps('pocketbase');
  try {
    final client = await _getClient(r);
    try {
      return await steps.run(label, () => fn(client));
    } finally {
      client.close();
    }
  } on PocketBaseException catch (e) {
    final match = RegExp(r'"message":"([^"]+)"').firstMatch(e.message);
    final detail = match?.group(1) ?? e.message;
    throw PackException('$label: $detail', 1);
  }
}

// ---------------------------------------------------------------------------
// backup
// ---------------------------------------------------------------------------

class PocketBaseBackupCommand extends FlutterPatcherCommand {
  PocketBaseBackupCommand() {
    addSubcommand(PocketBaseBackupCreateCommand());
    addSubcommand(PocketBaseBackupListCommand());
    addSubcommand(PocketBaseBackupDeleteCommand());
    addSubcommand(PocketBaseBackupRestoreCommand());
    addSubcommand(PocketBaseBackupDownloadCommand());
    addSubcommand(PocketBaseBackupUploadCommand());
  }

  @override
  String get name => 'backup';

  @override
  String get description => 'Manage PocketBase backups.';
}

class PocketBaseBackupCreateCommand extends FlutterPatcherCommand {
  PocketBaseBackupCreateCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('name', help: 'Backup file name.');
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a new backup.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · backup · create');
    await _pbStep(
      'Creating backup',
      (c) => c.createBackup(name: argResults!['name'] as String?),
      argResults!,
    );
    step(green('Backup created'));
  });
}

class PocketBaseBackupListCommand extends FlutterPatcherCommand {
  PocketBaseBackupListCommand() {
    _addBackendOptions(argParser);
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List available backups.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · backup · list');
    final backups = await _pbStep(
      'Listing backups',
      (c) => c.listBackups(),
      argResults!,
    );
    if (backups.isEmpty) {
      warn('No backups found.');
      return;
    }
    final rows = backups
        .map((b) => [cyan(b.key), b.sizeFormatted, b.modified])
        .toList();
    table('${backups.length} backups', ['KEY', 'SIZE', 'MODIFIED'], rows);
  });
}

class PocketBaseBackupDeleteCommand extends FlutterPatcherCommand {
  PocketBaseBackupDeleteCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('name', help: 'Backup key to delete.', mandatory: true);
  }

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete a backup.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · backup · delete');
    final key = argResults!['name'] as String;
    await _pbStep('Deleting $key', (c) => c.deleteBackup(key), argResults!);
    step(green('Deleted backup $key'));
  });
}

class PocketBaseBackupRestoreCommand extends FlutterPatcherCommand {
  PocketBaseBackupRestoreCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'name',
      help: 'Backup key to restore.',
      mandatory: true,
    );
  }

  @override
  String get name => 'restore';

  @override
  String get description => 'Restore a backup (restarts PB).';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · backup · restore');
    final key = argResults!['name'] as String;
    await _pbStep('Restoring $key', (c) => c.restoreBackup(key), argResults!);
    warn('PB will restart. Reconnect in a few seconds.');
  });
}

class PocketBaseBackupDownloadCommand extends FlutterPatcherCommand {
  PocketBaseBackupDownloadCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'name',
      help: 'Backup key to download.',
      mandatory: true,
    );
    argParser.addOption('output', help: 'Output directory.', defaultsTo: '.');
  }

  @override
  String get name => 'download';

  @override
  String get description => 'Download a backup file.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · backup · download');
    final key = argResults!['name'] as String;
    final output = argResults!['output'] as String;
    final (url, admin, pass) = _resolveBackend(argResults!);
    final dlClient = PocketBaseClient(url);
    try {
      await dlClient.authenticate(admin, pass);
      final token = dlClient.authToken;
      final dlUrl = dlClient.backupDownloadUrl(key, token);
      final bytes = await dlClient.downloadFileUnauth(dlUrl);
      final out = File(p.join(output, key));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes);
      step(green('Saved to ${out.path}'));
    } finally {
      dlClient.close();
    }
  });
}

class PocketBaseBackupUploadCommand extends FlutterPatcherCommand {
  PocketBaseBackupUploadCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('file', help: 'Backup zip to upload.', mandatory: true);
  }

  @override
  String get name => 'upload';

  @override
  String get description => 'Upload a backup zip file.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · backup · upload');
    final fp = argResults!['file'] as String;
    final f = File(fp);
    if (!await f.exists()) throw PackException('File not found: $fp', 64);
    final bytes = await f.readAsBytes();
    await _pbStep(
      'Uploading ${p.basename(fp)}',
      (c) => c.uploadBackup(bytes, name: p.basename(fp)),
      argResults!,
    );
    step(green('Uploaded ${p.basename(fp)}'));
  });
}

// ---------------------------------------------------------------------------
// export / import
// ---------------------------------------------------------------------------

class PocketBaseExportCommand extends FlutterPatcherCommand {
  PocketBaseExportCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('collection', help: 'Collection to export.');
    argParser.addOption('output', help: 'Output directory.', defaultsTo: '.');
  }

  @override
  String get name => 'export';

  @override
  String get description =>
      'Export collection(s) as JSON. Exports all if --collection omitted.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · export');
    final r = argResults!;
    final collection = r['collection'] as String?;
    final output = r['output'] as String;

    final (url, admin, pass) = _resolveBackend(r);
    final client = PocketBaseClient(url);
    try {
      await client.authenticate(admin, pass);

      final collections = <String>[];
      if (collection != null && collection.isNotEmpty) {
        collections.add(collection);
      } else {
        final all = await client.listCollections();
        for (final c in all) {
          final name = c['name'] as String? ?? '';
          if (name.isNotEmpty && !name.startsWith('_') && c['system'] != true) {
            collections.add(name);
          }
        }
        if (collections.isEmpty) {
          collections.addAll([
            'bundles',
            'channels',
            'audit_log',
            'bundles_patches',
          ]);
        }
      }

      for (final c in collections) {
        try {
          final records = await client.exportCollection(c);
          final outFile = File(p.join(output, '$c.json'));
          await outFile.parent.create(recursive: true);
          await outFile.writeAsString(
            const JsonEncoder.withIndent('  ').convert(records),
          );
          step('${records.length} records → ${outFile.path}');
        } catch (e) {
          warn('Failed to export $c: $e');
        }
      }
    } finally {
      client.close();
    }
  });
}

class PocketBaseImportCommand extends FlutterPatcherCommand {
  PocketBaseImportCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('file', help: 'JSON file to import.', mandatory: true);
    argParser.addOption('collection', help: 'Target collection name.');
  }

  @override
  String get name => 'import';

  @override
  String get description =>
      'Import records from a JSON file into a collection.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · import');
    final r = argResults!;
    final fp = r['file'] as String;
    final f = File(fp);
    if (!await f.exists()) throw PackException('File not found: $fp', 64);
    final json = jsonDecode(await f.readAsString()) as List<dynamic>;
    final records = json.cast<Map<String, dynamic>>();
    final target = r['collection'] as String? ?? p.basenameWithoutExtension(fp);
    await _pbStep(
      'Importing ${records.length} records into $target',
      (c) => c.importCollection(target, records),
      r,
    );
    step(green('${records.length} records imported into $target'));
  });
}

// ---------------------------------------------------------------------------
// admin
// ---------------------------------------------------------------------------

class PocketBaseAdminCommand extends FlutterPatcherCommand {
  PocketBaseAdminCommand() {
    addSubcommand(PocketBaseAdminCreateCommand());
    addSubcommand(PocketBaseAdminListCommand());
    addSubcommand(PocketBaseAdminUpdateCommand());
    addSubcommand(PocketBaseAdminDeleteCommand());
  }

  @override
  String get name => 'admin';

  @override
  String get description => 'Manage PocketBase admin accounts.';
}

class PocketBaseAdminCreateCommand extends FlutterPatcherCommand {
  PocketBaseAdminCreateCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('email', help: 'Admin email.', mandatory: true);
    argParser.addOption('password', help: 'Admin password.', mandatory: true);
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a new admin account.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · admin · create');
    final r = argResults!;
    final email = r['email'] as String;
    final password = r['password'] as String;
    final result = await _pbStep(
      'Creating admin $email',
      (c) => c.createAdmin(
        email: email,
        password: password,
        passwordConfirm: password,
      ),
      r,
    );
    stdout.writeln('  ${dim('→')} admin ${cyan(result['id'] ?? '?')} $email');
  });
}

class PocketBaseAdminListCommand extends FlutterPatcherCommand {
  PocketBaseAdminListCommand() {
    _addBackendOptions(argParser);
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List admin accounts.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · admin · list');
    final admins = await _pbStep(
      'Listing admins',
      (c) => c.listAdmins(),
      argResults!,
    );
    if (admins.isEmpty) {
      warn('No admins found.');
      return;
    }
    final rows = admins
        .map(
          (a) => [
            cyan(a['id']?.toString() ?? '?'),
            a['email']?.toString() ?? '?',
          ],
        )
        .toList();
    table('${admins.length} admins', ['ID', 'EMAIL'], rows);
  });
}

class PocketBaseAdminUpdateCommand extends FlutterPatcherCommand {
  PocketBaseAdminUpdateCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('id', help: 'Admin ID to update.', mandatory: true);
    argParser.addOption(
      'body',
      help: 'JSON fields to update.',
      mandatory: true,
    );
  }

  @override
  String get name => 'update';

  @override
  String get description => 'Update an admin account.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · admin · update');
    final r = argResults!;
    final id = r['id'] as String;
    final body = jsonDecode(r['body'] as String) as Map<String, dynamic>;
    await _pbStep('Updating admin $id', (c) => c.updateAdmin(id, body), r);
    step(green('Updated admin $id'));
  });
}

class PocketBaseAdminDeleteCommand extends FlutterPatcherCommand {
  PocketBaseAdminDeleteCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('id', help: 'Admin ID to delete.', mandatory: true);
  }

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete an admin account.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · admin · delete');
    final id = argResults!['id'] as String;
    await _pbStep('Deleting admin $id', (c) => c.deleteAdmin(id), argResults!);
    step(green('Deleted admin $id'));
  });
}

// ---------------------------------------------------------------------------
// migrate
// ---------------------------------------------------------------------------

class PocketBaseMigrateCommand extends FlutterPatcherCommand {
  PocketBaseMigrateCommand() {
    _addBackendOptions(argParser);
  }

  @override
  String get name => 'migrate';

  @override
  String get description => 'Re-run schema migration on a running PocketBase.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · migrate');
    final (url, admin, pass) = _resolveBackend(argResults!);
    final installer = PocketBaseSchemaInstaller(
      url: url,
      adminEmail: admin,
      adminPassword: pass,
    );
    final res = await installer.install();
    if (res.created.isNotEmpty) {
      step(green('Created: ${res.created.join(', ')}'));
    }
    if (res.skipped.isNotEmpty) {
      step('Already present: ${res.skipped.join(', ')}');
    }
  });
}

// ---------------------------------------------------------------------------
// health
// ---------------------------------------------------------------------------

class PocketBaseHealthCommand extends FlutterPatcherCommand {
  PocketBaseHealthCommand() {
    _addBackendOptions(argParser);
  }

  @override
  String get name => 'health';

  @override
  String get description => 'Check PocketBase health.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · health');
    final health = await _pbStep(
      'health',
      (c) => c.healthDetailed(),
      argResults!,
    );
    final code = health['code'] as int? ?? 0;
    final message = health['message'] as String? ?? '';
    final data = health['data'] as Map<String, dynamic>? ?? {};
    final status = code == 200 ? green('healthy') : red('unhealthy');
    step('status      $status');
    step('message     $message');
    step('canBackup   ${data['canBackup'] ?? false}');
  });
}

// ---------------------------------------------------------------------------
// logs
// ---------------------------------------------------------------------------

class PocketBaseLogsCommand extends FlutterPatcherCommand {
  PocketBaseLogsCommand() {
    addSubcommand(PocketBaseLogsListCommand());
    addSubcommand(PocketBaseLogsStatsCommand());
    addSubcommand(PocketBaseLogsTruncateCommand());
  }

  @override
  String get name => 'logs';

  @override
  String get description => 'Manage PocketBase logs.';
}

class PocketBaseLogsListCommand extends FlutterPatcherCommand {
  PocketBaseLogsListCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('filter', help: 'PB filter expression.');
    argParser.addOption('sort', help: 'Sort field.', defaultsTo: '-created');
    argParser.addOption('page', help: 'Page number.', defaultsTo: '1');
    argParser.addOption('per-page', help: 'Items per page.', defaultsTo: '30');
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List request logs.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · logs · list');
    final r = argResults!;
    final data = await _pbStep(
      'Fetching logs',
      (c) => c.listLogs(
        filter: r['filter'] as String?,
        sort: r['sort'] as String?,
        page: int.tryParse(r['page'] as String? ?? '1') ?? 1,
        perPage: int.tryParse(r['per-page'] as String? ?? '30') ?? 30,
      ),
      r,
    );
    final items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
    final total = data['totalItems'] as int? ?? 0;
    if (items.isEmpty) {
      warn('No logs found.');
      return;
    }
    final rows = items.map((log) {
      final level = log['level'] as int? ?? 0;
      final lvl = level == 0
          ? green('INFO')
          : level == 1
          ? yellow('WARN')
          : red('ERROR');
      final msg = (log['message'] as String? ?? '').length > 60
          ? '${(log['message'] as String).substring(0, 57)}...'
          : log['message'] as String? ?? '';
      return [lvl, _safeSubstring(log['created']?.toString(), 19), msg];
    }).toList();
    table('$total logs', ['LEVEL', 'TIME', 'MESSAGE'], rows);
  });
}

class PocketBaseLogsStatsCommand extends FlutterPatcherCommand {
  PocketBaseLogsStatsCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('filter', help: 'PB filter expression.');
  }

  @override
  String get name => 'stats';

  @override
  String get description => 'Show hourly log statistics.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · logs · stats');
    final stats = await _pbStep(
      'Fetching log stats',
      (c) => c.getLogStats(filter: argResults!['filter'] as String?),
      argResults!,
    );
    if (stats.isEmpty) {
      warn('No stats available.');
      return;
    }
    final rows = stats
        .map(
          (s) => [
            _safeSubstring(s['date']?.toString(), 16),
            '${s['total'] ?? 0}',
          ],
        )
        .toList();
    table('${stats.length} entries', ['TIME', 'COUNT'], rows);
  });
}

class PocketBaseLogsTruncateCommand extends FlutterPatcherCommand {
  PocketBaseLogsTruncateCommand() {
    _addBackendOptions(argParser);
  }

  @override
  String get name => 'truncate';

  @override
  String get description => 'Delete all logs.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · logs · truncate');
    await _pbStep('Truncating logs', (c) => c.truncateLogs(), argResults!);
    step(green('All logs deleted'));
  });
}

// ---------------------------------------------------------------------------
// records
// ---------------------------------------------------------------------------

class PocketBaseRecordsCommand extends FlutterPatcherCommand {
  PocketBaseRecordsCommand() {
    addSubcommand(PocketBaseRecordsListCommand());
    addSubcommand(PocketBaseRecordsGetCommand());
    addSubcommand(PocketBaseRecordsCreateCommand());
    addSubcommand(PocketBaseRecordsUpdateCommand());
    addSubcommand(PocketBaseRecordsDeleteCommand());
    addSubcommand(PocketBaseRecordsBatchCommand());
  }

  @override
  String get name => 'records';

  @override
  String get description => 'CRUD operations on collection records.';
}

class PocketBaseRecordsListCommand extends FlutterPatcherCommand {
  PocketBaseRecordsListCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'collection',
      help: 'Collection name.',
      mandatory: true,
    );
    argParser.addOption('filter', help: 'PB filter expression.');
    argParser.addOption('sort', help: 'Sort field.');
    argParser.addOption('page', help: 'Page number.', defaultsTo: '1');
    argParser.addOption('per-page', help: 'Items per page.', defaultsTo: '30');
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List records in a collection.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · records · list');
    final r = argResults!;
    final data = await _pbStep(
      'Listing ${r['collection']}',
      (c) => c.listRecords<dynamic>(
        r['collection'] as String,
        (j) => j,
        filter: r['filter'] as String?,
        sort: r['sort'] as String?,
        page: int.tryParse(r['page'] as String? ?? '1') ?? 1,
        perPage: int.tryParse(r['per-page'] as String? ?? '30') ?? 30,
      ),
      r,
    );
    if (data.items.isEmpty) {
      warn('No records found.');
      return;
    }
    final rows = data.items.map((r) {
      final m = r as Map<String, dynamic>;
      final label =
          m['name']?.toString() ??
          m['updated']?.toString() ??
          m['created']?.toString() ??
          '';
      return [cyan(m['id']?.toString() ?? '?'), label];
    }).toList();
    table('${data.totalItems} records', ['ID', 'LABEL'], rows);
  });
}

class PocketBaseRecordsGetCommand extends FlutterPatcherCommand {
  PocketBaseRecordsGetCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'collection',
      help: 'Collection name.',
      mandatory: true,
    );
    argParser.addOption('id', help: 'Record ID.', mandatory: true);
  }

  @override
  String get name => 'get';

  @override
  String get description => 'Get a single record.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · records · get');
    final r = argResults!;
    final record = await _pbStep(
      'Getting ${r['collection']}/${r['id']}',
      (c) => c.getRecord<dynamic>(
        r['collection'] as String,
        r['id'] as String,
        (j) => j,
      ),
      r,
    );
    if (record == null) {
      warn('Record not found.');
      return;
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(record));
  });
}

class PocketBaseRecordsCreateCommand extends FlutterPatcherCommand {
  PocketBaseRecordsCreateCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'collection',
      help: 'Collection name.',
      mandatory: true,
    );
    argParser.addOption('body', help: 'JSON body.', mandatory: true);
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a record.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · records · create');
    final r = argResults!;
    final body = jsonDecode(r['body'] as String) as Map<String, dynamic>;
    final record = await _pbStep(
      'Creating record in ${r['collection']}',
      (c) => c.createRecord<dynamic>(r['collection'] as String, body, (j) => j),
      r,
    );
    stdout.writeln(
      '  ${dim('→')} record ${cyan((record as Map)['id']?.toString() ?? '?')}',
    );
  });
}

class PocketBaseRecordsUpdateCommand extends FlutterPatcherCommand {
  PocketBaseRecordsUpdateCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'collection',
      help: 'Collection name.',
      mandatory: true,
    );
    argParser.addOption('id', help: 'Record ID.', mandatory: true);
    argParser.addOption('body', help: 'JSON body.', mandatory: true);
  }

  @override
  String get name => 'update';

  @override
  String get description => 'Update a record.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · records · update');
    final r = argResults!;
    final body = jsonDecode(r['body'] as String) as Map<String, dynamic>;
    await _pbStep(
      'Updating ${r['collection']}/${r['id']}',
      (c) => c.updateRecord<dynamic>(
        r['collection'] as String,
        r['id'] as String,
        body,
        (j) => j,
      ),
      r,
    );
    step(green('Updated ${r['collection']}/${r['id']}'));
  });
}

class PocketBaseRecordsDeleteCommand extends FlutterPatcherCommand {
  PocketBaseRecordsDeleteCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'collection',
      help: 'Collection name.',
      mandatory: true,
    );
    argParser.addOption('id', help: 'Record ID.', mandatory: true);
  }

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete a record.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · records · delete');
    final r = argResults!;
    await _pbStep(
      'Deleting ${r['collection']}/${r['id']}',
      (c) => c.deleteRecord(r['collection'] as String, r['id'] as String),
      r,
    );
    step(green('Deleted ${r['collection']}/${r['id']}'));
  });
}

class PocketBaseRecordsBatchCommand extends FlutterPatcherCommand {
  PocketBaseRecordsBatchCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'requests',
      help: 'JSON array of request objects.',
      mandatory: true,
    );
  }

  @override
  String get name => 'batch';

  @override
  String get description =>
      'Execute multiple record operations in a single transaction.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · records · batch');
    final requests =
        jsonDecode(argResults!['requests'] as String) as List<dynamic>;
    final body = requests.cast<Map<String, dynamic>>();
    final results = await _pbStep(
      'Executing ${body.length} batch requests',
      (c) => c.batch(body),
      argResults!,
    );
    for (final (i, r) in results.indexed) {
      final status = r['status'] as int? ?? 0;
      final ok = status >= 200 && status < 300;
      step('${ok ? green('ok') : red('fail')} [${i + 1}] HTTP $status');
    }
  });
}
// ---------------------------------------------------------------------------

class PocketBaseCollectionsCommand extends FlutterPatcherCommand {
  PocketBaseCollectionsCommand() {
    addSubcommand(PocketBaseCollectionsListCommand());
    addSubcommand(PocketBaseCollectionsViewCommand());
    addSubcommand(PocketBaseCollectionsCreateCommand());
    addSubcommand(PocketBaseCollectionsUpdateCommand());
    addSubcommand(PocketBaseCollectionsDeleteCommand());
    addSubcommand(PocketBaseCollectionsTruncateCommand());
    addSubcommand(PocketBaseCollectionsImportCommand());
  }

  @override
  String get name => 'collections';

  @override
  String get description => 'Manage PocketBase collections.';
}

class PocketBaseCollectionsListCommand extends FlutterPatcherCommand {
  PocketBaseCollectionsListCommand() {
    _addBackendOptions(argParser);
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List all collections.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · collections · list');
    final cols = await _pbStep(
      'Listing collections',
      (c) => c.listCollections(),
      argResults!,
    );
    if (cols.isEmpty) {
      warn('No collections found.');
      return;
    }
    final rows = cols
        .map(
          (c) => [
            cyan(c['name']?.toString() ?? '?'),
            c['type']?.toString() ?? '?',
            '${(c['fields'] as List?)?.length ?? 0} fields',
          ],
        )
        .toList();
    table('${cols.length} collections', ['NAME', 'TYPE', 'FIELDS'], rows);
  });
}

class PocketBaseCollectionsViewCommand extends FlutterPatcherCommand {
  PocketBaseCollectionsViewCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'name',
      help: 'Collection name or ID.',
      mandatory: true,
    );
  }

  @override
  String get name => 'view';

  @override
  String get description => 'View a collection schema.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · collections · view');
    final name = argResults!['name'] as String;
    final col = await _pbStep(
      'Viewing $name',
      (c) => c.getCollection(name),
      argResults!,
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(col));
  });
}

class PocketBaseCollectionsCreateCommand extends FlutterPatcherCommand {
  PocketBaseCollectionsCreateCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'body',
      help: 'JSON collection definition.',
      mandatory: true,
    );
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a new collection.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · collections · create');
    final body =
        jsonDecode(argResults!['body'] as String) as Map<String, dynamic>;
    await _pbStep(
      'Creating ${body['name'] ?? 'collection'}',
      (c) => c.createCollection(body),
      argResults!,
    );
    step(green('Created ${body['name'] ?? 'collection'}'));
  });
}

class PocketBaseCollectionsUpdateCommand extends FlutterPatcherCommand {
  PocketBaseCollectionsUpdateCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'name',
      help: 'Collection name or ID.',
      mandatory: true,
    );
    argParser.addOption(
      'body',
      help: 'JSON fields to update.',
      mandatory: true,
    );
  }

  @override
  String get name => 'update';

  @override
  String get description => 'Update a collection.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · collections · update');
    final r = argResults!;
    final name = r['name'] as String;
    final body = jsonDecode(r['body'] as String) as Map<String, dynamic>;
    await _pbStep('Updating $name', (c) => c.updateCollection(name, body), r);
    step(green('Updated $name'));
  });
}

class PocketBaseCollectionsDeleteCommand extends FlutterPatcherCommand {
  PocketBaseCollectionsDeleteCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'name',
      help: 'Collection name or ID.',
      mandatory: true,
    );
  }

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete a collection.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · collections · delete');
    final name = argResults!['name'] as String;
    await _pbStep(
      'Deleting $name',
      (c) => c.deleteCollection(name),
      argResults!,
    );
    step(green('Deleted collection $name'));
  });
}

class PocketBaseCollectionsTruncateCommand extends FlutterPatcherCommand {
  PocketBaseCollectionsTruncateCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'name',
      help: 'Collection name or ID.',
      mandatory: true,
    );
  }

  @override
  String get name => 'truncate';

  @override
  String get description => 'Delete all records in a collection.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · collections · truncate');
    final name = argResults!['name'] as String;
    await _pbStep(
      'Truncating $name',
      (c) => c.truncateCollection(name),
      argResults!,
    );
    step(green('Truncated $name'));
  });
}

class PocketBaseCollectionsImportCommand extends FlutterPatcherCommand {
  PocketBaseCollectionsImportCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'file',
      help: 'JSON file with collections config.',
      mandatory: true,
    );
    argParser.addFlag(
      'delete-missing',
      help: 'Delete collections not in file.',
      defaultsTo: false,
    );
  }

  @override
  String get name => 'import';

  @override
  String get description => 'Import collections from a JSON file.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · collections · import');
    final r = argResults!;
    final fp = r['file'] as String;
    final f = File(fp);
    if (!await f.exists()) throw PackException('File not found: $fp', 64);
    final json = jsonDecode(await f.readAsString()) as List<dynamic>;
    final cols = json.cast<Map<String, dynamic>>();
    await _pbStep(
      'Importing ${cols.length} collections',
      (c) =>
          c.importCollections(cols, deleteMissing: r['delete-missing'] as bool),
      r,
    );
    step(green('Imported ${cols.length} collections'));
  });
}

// ---------------------------------------------------------------------------
// settings
// ---------------------------------------------------------------------------

class PocketBaseSettingsCommand extends FlutterPatcherCommand {
  PocketBaseSettingsCommand() {
    addSubcommand(PocketBaseSettingsListCommand());
    addSubcommand(PocketBaseSettingsUpdateCommand());
    addSubcommand(PocketBaseSettingsTestS3Command());
    addSubcommand(PocketBaseSettingsTestEmailCommand());
  }

  @override
  String get name => 'settings';

  @override
  String get description => 'Manage PocketBase application settings.';
}

class PocketBaseSettingsListCommand extends FlutterPatcherCommand {
  PocketBaseSettingsListCommand() {
    _addBackendOptions(argParser);
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List all application settings.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · settings · list');
    final settings = await _pbStep(
      'Fetching settings',
      (c) => c.listSettings(),
      argResults!,
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(settings));
  });
}

class PocketBaseSettingsUpdateCommand extends FlutterPatcherCommand {
  PocketBaseSettingsUpdateCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'body',
      help: 'JSON object with settings to update.',
      mandatory: true,
    );
  }

  @override
  String get name => 'update';

  @override
  String get description => 'Update application settings.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · settings · update');
    final body =
        jsonDecode(argResults!['body'] as String) as Map<String, dynamic>;
    await _pbStep(
      'Updating settings',
      (c) => c.updateSettings(body),
      argResults!,
    );
    step(green('Settings updated'));
  });
}

class PocketBaseSettingsTestS3Command extends FlutterPatcherCommand {
  PocketBaseSettingsTestS3Command() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'filesystem',
      help: 'Storage filesystem to test.',
      defaultsTo: 'storage',
    );
  }

  @override
  String get name => 'test-s3';

  @override
  String get description => 'Test S3 storage connection.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · settings · test-s3');
    final fs = argResults!['filesystem'] as String;
    await _pbStep('Testing S3 ($fs)', (c) => c.testS3(fs), argResults!);
    step(green('S3 connection OK'));
  });
}

class PocketBaseSettingsTestEmailCommand extends FlutterPatcherCommand {
  PocketBaseSettingsTestEmailCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('email', help: 'Recipient email.', mandatory: true);
    argParser.addOption('template', help: 'Email template.', mandatory: true);
    argParser.addOption('collection', help: 'Auth collection name or ID.');
  }

  @override
  String get name => 'test-email';

  @override
  String get description => 'Send a test email.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · settings · test-email');
    final r = argResults!;
    await _pbStep(
      'Sending test email to ${r['email']}',
      (c) => c.testEmail(
        email: r['email'] as String,
        template: r['template'] as String,
        collection: r['collection'] as String?,
      ),
      r,
    );
    step(green('Test email sent'));
  });
}

// ---------------------------------------------------------------------------
// sql
// ---------------------------------------------------------------------------

class PocketBaseSqlCommand extends FlutterPatcherCommand {
  PocketBaseSqlCommand() {
    _addBackendOptions(argParser);
    argParser.addOption(
      'query',
      help: 'SQL query to execute.',
      mandatory: true,
    );
  }

  @override
  String get name => 'sql';

  @override
  String get description => 'Execute a raw SQL query.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · sql');
    final query = argResults!['query'] as String;
    final result = await _pbStep(
      'Executing query',
      (c) => c.runSql(query),
      argResults!,
    );
    final columns = (result['columns'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final rows = (result['rows'] as List? ?? []).cast<List<dynamic>>();
    if (rows.isNotEmpty) {
      final colNames = columns.map((c) => '${c['name']}').toList();
      final tableRows = rows.map((r) => r.map((v) => '$v').toList()).toList();
      table('${rows.length} rows', colNames, tableRows);
    } else {
      step('Query executed. ${result['affectedRows'] ?? 0} rows affected.');
    }
  });
}

// ---------------------------------------------------------------------------
// crons
// ---------------------------------------------------------------------------

class PocketBaseCronsCommand extends FlutterPatcherCommand {
  PocketBaseCronsCommand() {
    addSubcommand(PocketBaseCronsListCommand());
    addSubcommand(PocketBaseCronsRunCommand());
  }

  @override
  String get name => 'crons';

  @override
  String get description => 'Manage PocketBase cron jobs.';
}

class PocketBaseCronsListCommand extends FlutterPatcherCommand {
  PocketBaseCronsListCommand() {
    _addBackendOptions(argParser);
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List all registered cron jobs.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · crons · list');
    final crons = await _pbStep(
      'Fetching cron jobs',
      (c) => c.listCrons(),
      argResults!,
    );
    if (crons.isEmpty) {
      warn('No cron jobs registered.');
      return;
    }
    final rows = crons
        .map(
          (c) => [
            cyan(c['id']?.toString() ?? '?'),
            c['expression']?.toString() ?? '?',
          ],
        )
        .toList();
    table('${crons.length} cron jobs', ['ID', 'EXPRESSION'], rows);
  });
}

class PocketBaseCronsRunCommand extends FlutterPatcherCommand {
  PocketBaseCronsRunCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('job-id', help: 'Cron job ID to run.', mandatory: true);
  }

  @override
  String get name => 'run';

  @override
  String get description => 'Trigger a cron job by ID.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · crons · run');
    final jobId = argResults!['job-id'] as String;
    await _pbStep('Running $jobId', (c) => c.runCron(jobId), argResults!);
    step(green('Cron $jobId triggered'));
  });
}

// ---------------------------------------------------------------------------
// query
// ---------------------------------------------------------------------------

class PocketBaseQueryCommand extends FlutterPatcherCommand {
  PocketBaseQueryCommand() {
    _addBackendOptions(argParser);
    argParser.addOption('method', help: 'HTTP method.', defaultsTo: 'GET');
    argParser.addOption('path', help: 'API path.', mandatory: true);
    argParser.addOption('body', help: 'JSON body for POST/PATCH.');
  }

  @override
  String get name => 'query';

  @override
  String get description => 'Execute an arbitrary API request.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · query');
    final r = argResults!;
    final method = r['method'] as String;
    final path = r['path'] as String;
    final bodyStr = r['body'] as String?;
    Map<String, dynamic>? body;
    if (bodyStr != null && bodyStr.isNotEmpty) {
      body = jsonDecode(bodyStr) as Map<String, dynamic>;
    }
    final (url, admin, pass) = _resolveBackend(r);
    final client = PocketBaseClient(url);
    try {
      await client.authenticate(admin, pass);
      final res = await client.rawRequest(method, path, body: body);
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(jsonDecode(res.body)),
      );
    } finally {
      client.close();
    }
  });
}

// ---------------------------------------------------------------------------
// config
// ---------------------------------------------------------------------------

class PocketBaseConfigCommand extends FlutterPatcherCommand {
  PocketBaseConfigCommand() {
    _addBackendOptions(argParser);
  }

  @override
  String get name => 'config';

  @override
  String get description => 'Show current PocketBase configuration.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('pocketbase · config');
    final (url, admin, _) = _resolveBackend(argResults!);
    final paths = PocketBaseInstallPaths.resolve();
    final exists = await paths.binaryPath.exists();
    box('config', [
      kv('url', cyan(url)),
      kv('admin', admin),
      kv('version', paths.version),
      kv(
        'binary',
        exists ? green(paths.binaryPath.path) : red('not installed'),
      ),
    ]);
  });
}
