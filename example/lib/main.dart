import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterPatcher.configureSupabase(
    SupabaseUpdateConfig(
      supabaseUrl: const String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: 'https://your-project.supabase.co',
      ),
      anonKey: const String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue: '',
      ),
      bucket: const String.fromEnvironment(
        'SUPABASE_BUCKET',
        defaultValue: 'bundles',
      ),
      channel: const String.fromEnvironment(
        'CHANNEL',
        defaultValue: 'production',
      ),
      platform: Platform.android,
      updateStrategy: UpdateStrategy.appVersion,
      appVersion: const String.fromEnvironment(
        'APP_VERSION',
        defaultValue: '1.0.0',
      ),
    ),
  );

  await FlutterPatcher.init(autoApplyUpdates: true);

  runApp(const FlutterOtaApp(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: FlutterPatcher.navigatorKey,
    title: 'Flutter OTA Kit',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      useMaterial3: true,
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _status = 'Ready';
  String _lastResult = '';

  Future<void> _checkForUpdate() async {
    setState(() {
      _status = 'Checking for update...';
      _lastResult = '';
    });

    try {
      final result = await FlutterPatcher.checkForUpdate();
      if (!mounted) return;

      if (result.hasUpdate && result.patch != null) {
        setState(() {
          _status = 'Update available';
          _lastResult =
              'Version: ${result.id}\n'
              'Force: ${result.shouldForceUpdate}\n'
              'Message: ${result.message ?? "(none)"}';
        });
      } else {
        setState(() {
          _status = 'Up to date';
          _lastResult = 'No update available.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Error';
        _lastResult = e.toString();
      });
    }
  }

  Future<void> _applyUpdate() async {
    setState(() {
      _status = 'Applying update...';
      _lastResult = '';
    });

    try {
      final result = await FlutterPatcher.checkForUpdate();
      if (!mounted) return;

      if (!result.hasUpdate || result.patch == null) {
        setState(() {
          _status = 'No update';
          _lastResult = 'Nothing to apply.';
        });
        return;
      }

      final applied = await FlutterPatcher.applyUpdate(
        result,
        onProgress: (p) {
          if (mounted) {
            setState(() => _status = 'Progress: ${p.phase.name}');
          }
        },
      );
      if (!mounted) return;

      setState(() {
        _status = applied.ok ? 'Applied!' : 'Failed';
        _lastResult =
            'ok: ${applied.ok}\n'
            'error: ${applied.error?.name}\n'
            'message: ${applied.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Error';
        _lastResult = e.toString();
      });
    }
  }

  Future<void> _rollback() async {
    setState(() {
      _status = 'Rolling back...';
      _lastResult = '';
    });

    try {
      await FlutterPatcher.rollback();
      if (!mounted) return;
      setState(() {
        _status = 'Rolled back';
        _lastResult = 'Patch deleted. Restart to use built-in version.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Error';
        _lastResult = e.toString();
      });
    }
  }

  Future<void> _showDiagnostics() async {
    final diag = await FlutterPatcher.lastBootDiagnostic;
    if (!mounted) return;

    final buf = StringBuffer();
    if (diag == null) {
      buf.writeln('No diagnostic recorded yet.');
    } else {
      buf.writeln('Status: ${diag.status.name}');
      if (diag.patchVersion != null) buf.writeln('Patch v: ${diag.patchVersion}');
      if (diag.patchTargetVersionCode != null) {
        buf.writeln('Patch vc: ${diag.patchTargetVersionCode}');
      }
      if (diag.appVersionCode != null) buf.writeln('App vc: ${diag.appVersionCode}');
      if (diag.crashCount != null) buf.writeln('Crashes: ${diag.crashCount}');
      if (diag.message != null) buf.writeln('Message: ${diag.message}');
    }

    setState(() {
      _status = 'Diagnostics';
      _lastResult = buf.toString();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Flutter OTA Kit'),
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'OTA v1.0.1 — Purple theme active',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_lastResult.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _lastResult,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _checkForUpdate,
              child: const Text('Check for Update'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _applyUpdate,
              child: const Text('Apply Update'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _rollback,
              child: const Text('Rollback'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _showDiagnostics,
              child: const Text('Show Diagnostics'),
            ),
          ],
        ),
      ),
    ),
  );
}
