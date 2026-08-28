import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_patcher/flutter_patcher.dart';

import 'diag_card.dart';
import 'log_panel.dart';

const _demoImage = 'assets/patch_demo.png';
const _bundledAssetPatch = 'assets/asset_patch_preload.zip';
const _supabaseUrl = 'https://lwsirrxhycfdttlumlfu.supabase.co';
const _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx3c2lycnhoeWNmZHR0bHVtbGZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc3NDA5NzEsImV4cCI6MjEwMzMxNjk3MX0.cKrlIy1otU9PfIIR-gGA2OfN84H8mlsE00hJ7cq5zf8';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterPatcher.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'flutter_patcher example',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
    ),
    home: const Demo(),
  );
}

class Demo extends StatefulWidget {
  const Demo({super.key});

  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  final _log = LogController();

  Future<void> _applyBundledAssetPatch() async {
    _log.log('loading bundled patch.zip...');
    final bytes = (await rootBundle.load(
      _bundledAssetPatch,
    )).buffer.asUint8List();

    final result = await FlutterPatcher.applyPatchBytes(
      bytes,
      version: 'asset-demo-1',
      onProgress: (p) => _log.log('  [${p.phase.name}]'),
    );

    _log.log(
      result.ok
          ? 'APPLIED: force-stop and reopen to see the image replacement'
          : 'failed: ${result.error?.name} / ${result.message}',
    );
    DiagCard.refresh();
  }

  Future<void> _rollback() async {
    await FlutterPatcher.rollback();
    _log.log('ROLLED BACK: force-stop and reopen to restore the APK image');
    DiagCard.refresh();
  }

  /// Demonstrates the hosted **Supabase** wiring: configure the built-in
  /// Supabase update source (talks directly to the Supabase REST API — no
  /// separate server process needed) and apply the latest production bundle.
  Future<void> _checkWithSupabase() async {
    try {
      FlutterPatcher.configureSupabase(SupabaseUpdateConfig(
        supabaseUrl: _supabaseUrl,
        anonKey: _supabaseAnonKey,
        bucket: 'bundles',
        channel: 'production',
        platform: Platform.android,
        updateStrategy: UpdateStrategy.appVersion,
        appVersion: '1.0.0',
        sdkVersion: '1.0.0',
      ));
      _log.log('Supabase: checking production channel (appVersion 1.0.0)...');
      final result = await FlutterPatcher.checkForUpdate();
      if (!result.hasUpdate || result.patch == null) {
        _log.log('Supabase: no update available');
        return;
      }
      final patch = result.patch!;
      _log.log('Supabase: update ${patch.version} (force=${result.shouldForceUpdate}) '
          '-> downloading');
      final apply = await FlutterPatcher.applyPatch(
        patch,
        onProgress: (p) => _log.log('  [${p.phase.name}]'),
      );
      _log.log(
        apply.ok
            ? 'Supabase APPLIED (${patch.version}): force-stop and reopen'
            : 'Supabase failed: ${apply.error?.name} / ${apply.message}',
      );
      DiagCard.refresh();
    } catch (e) {
      _log.log('Supabase error: $e');
    }
  }

  void _snack(String label, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label button from OTA code patch!',
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _otaHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          colors: [
            Color(0xFFFF5252),
            Color(0xFFFFC107),
            Color(0xFF4CAF50),
            Color(0xFF2979FF),
          ],
        ).createShader(r),
        child: const Text(
          'CODE PATCH ota-code-3 IS LIVE!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FilledButton(
            onPressed: () => _snack('RED', Colors.red),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('RED'),
          ),
          FilledButton(
            onPressed: () => _snack('GREEN', Colors.green),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('GREEN'),
          ),
          FilledButton(
            onPressed: () => _snack('BLUE', Colors.blue),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('BLUE'),
          ),
        ],
      ),
      const SizedBox(height: 12),
    ],
  );

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('flutter_patcher example')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _otaHeader(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 96,
                  height: 54,
                  child: Image.asset(_demoImage, fit: BoxFit.contain),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'asset key',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      SizedBox(height: 2),
                      Text(
                        _demoImage,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const DiagCard(),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _applyBundledAssetPatch,
              child: const Text('Apply patch'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _checkWithSupabase,
              child: const Text('Check via Supabase'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _rollback, child: const Text('Rollback')),
            const SizedBox(height: 16),
            Expanded(child: LogPanel(controller: _log)),
          ],
        ),
      ),
    ),
  );
}
