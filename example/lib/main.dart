import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_patcher/flutter_patcher.dart';

import 'diag_card.dart';
import 'log_panel.dart';

const _demoImage = 'assets/patch_demo.png';
const _bundledAssetPatch = 'assets/asset_patch_preload.zip';
const _defaultOtaUrl =
    'https://8080-firebase-cominfectedinstaf-1766575467659.cluster-zumahodzirciuujpqvsniawo3o.cloudworkstations.dev';

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
  final _otaUrl = TextEditingController(text: _defaultOtaUrl);

  Future<void> _checkAndApplyOta() async {
    final base = _otaUrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      _log.log('OTA: url is empty');
      return;
    }
    try {
      _log.log('OTA: checking $base/check ...');
      final check = await FlutterPatcher.checkUpdate('$base/check');
      if (!check.hasUpdate || check.patch == null) {
        _log.log('OTA: no update available');
        return;
      }
      final patch = check.patch!;
      // The mock server reflects the Host header as http://; the studio proxy
      // is HTTPS-only and Android blocks cleartext, so rewrite the scheme.
      final fixed = PatchInfo(
        version: patch.version,
        patchUrl: patch.patchUrl.replaceFirst('http://', 'https://'),
        md5: patch.md5,
        signature: patch.signature,
        targetVersionCode: patch.targetVersionCode,
        raw: patch.raw,
      );
      _log.log('OTA: update ${fixed.version} -> downloading');
      final result = await FlutterPatcher.applyPatch(
        fixed,
        onProgress: (p) => _log.log('  [${p.phase.name}]'),
      );
      _log.log(
        result.ok
            ? 'OTA APPLIED (${patch.version}): force-stop and reopen'
            : 'OTA failed: ${result.error?.name} / ${result.message}',
      );
      DiagCard.refresh();
    } catch (e) {
      _log.log('OTA error: $e');
    }
  }

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

  /// Demonstrates the hot-updater-compatible server wiring: configure the
  /// built-in server-backed source (which talks to any flutter_patcher server,
  /// itself backed by Supabase / Postgres / Cloudflare / AWS plugins), check
  /// for an update, and apply it.
  Future<void> _checkWithServer() async {
    final base = _otaUrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      _log.log('Server: url is empty');
      return;
    }
    try {
      FlutterPatcher.configureServer(ServerUpdateConfig(
        baseUrl: base,
        channel: 'production',
        platform: Platform.android,
        updateStrategy: UpdateStrategy.fingerprint,
        fingerprintHash: 'demo-fingerprint',
        sdkVersion: '1.0.0',
      ));
      _log.log('Server: checking $base (fingerprint strategy)...');
      final result = await FlutterPatcher.checkForUpdate();
      if (!result.hasUpdate || result.patch == null) {
        _log.log('Server: no update available');
        return;
      }
      final patch = result.patch!;
      _log.log('Server: update ${patch.version} (force=${result.shouldForceUpdate}) '
          '-> downloading');
      final apply = await FlutterPatcher.applyPatch(
        patch,
        onProgress: (p) => _log.log('  [${p.phase.name}]'),
      );
      _log.log(
        apply.ok
            ? 'Server APPLIED (${patch.version}): force-stop and reopen'
            : 'Server failed: ${apply.error?.name} / ${apply.message}',
      );
      DiagCard.refresh();
    } catch (e) {
      _log.log('Server error: $e');
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
    _otaUrl.dispose();
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
            TextField(
              controller: _otaUrl,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              decoration: const InputDecoration(
                labelText: 'OTA base URL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _checkAndApplyOta,
              child: const Text('Check & apply OTA'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _checkWithServer,
              child: const Text('Check via flutter_patcher server'),
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
