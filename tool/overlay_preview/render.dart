// Dev-only harness that renders the shipped OtaProgressOverlay to PNGs so the
// terminal overlay can be reviewed without a device.
//
//   flutter test tool/overlay_preview/render.dart --update-goldens
//
// Output: tool/overlay_preview/previews/*.png
// Not part of the published package or CI.

import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _canvas = Size(390, 844);

Future<void> _shoot(
  WidgetTester tester,
  String file,
  OtaOverlayState state, {
  VoidCallback? onRetry,
}) async {
  tester.view.physicalSize = _canvas;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: OtaProgressOverlay(
          state: ValueNotifier(state),
          onRetry: onRetry,
        ),
      ),
    ),
  );
  // Advance a few frames so the braille spinner shows a non-initial glyph.
  await tester.pump(const Duration(milliseconds: 120));
  await expectLater(
    find.byType(OtaProgressOverlay),
    matchesGoldenFile('previews/$file'),
  );
}

void main() {
  testWidgets('downloading', (t) async {
    await _shoot(
      t,
      'overlay_downloading.png',
      const OtaOverlayState(
        phase: PatchApplyPhase.downloading,
        fraction: 0.62,
        currentVersion: '1.4.0',
        targetVersion: '1.4.1',
        channel: 'production',
        bundleHash: 'a1b2c3d4',
        totalBytes: 8 * 1048576,
        bytesReceived: 5 * 1048576,
        bytesPerSec: 2 * 1048576 + 314572, // ~2.3 MB/s
        activeStep: 1,
        message: 'New onboarding flow + crash fixes',
        logs: [
          LogLine('gray', 'channel  production'),
          LogLine('gray', 'bundle   a1b2c3d4'),
          LogLine('cyan', 'resolve  download url'),
          LogLine('gray', 'download 8.0MB  62%'),
        ],
      ),
    );
  });

  testWidgets('verifying', (t) async {
    await _shoot(
      t,
      'overlay_verifying.png',
      const OtaOverlayState(
        phase: PatchApplyPhase.verifying,
        currentVersion: '1.4.0',
        targetVersion: '1.4.1',
        channel: 'production',
        bundleHash: 'a1b2c3d4',
        totalBytes: 8 * 1048576,
        activeStep: 2,
        message: 'New onboarding flow + crash fixes',
        logs: [
          LogLine('green', 'download complete ✓'),
          LogLine('cyan', 'verify   md5 match ✓'),
          LogLine('cyan', 'verify   checking signature…'),
        ],
      ),
    );
  });

  testWidgets('error', (t) async {
    await _shoot(
      t,
      'overlay_error.png',
      const OtaOverlayState(
        hasError: true,
        errorText: 'MD5 mismatch',
        errorHint: 'Close the app and reopen to retry.',
        currentVersion: '1.4.0',
        targetVersion: '1.4.1',
        channel: 'production',
        bundleHash: 'a1b2c3d4',
        totalBytes: 8 * 1048576,
        activeStep: 2,
        canRetry: true,
        logs: [
          LogLine('green', 'download complete ✓'),
          LogLine('red', 'error    md5 mismatch: expected a1b2c3…'),
          LogLine('yellow', 'action   rolling back to base apk'),
        ],
      ),
      onRetry: () {},
    );
  });
}
