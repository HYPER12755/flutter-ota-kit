// Golden tests for the forced-update progress overlay.
//
// These produce a visual record of what the overlay looks like in each state
// (idle / downloading / verifying / finalizing / error) and on each platform
// theme (light / dark). Run `flutter test --update-goldens` to regenerate.

import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pump the overlay into a small MediaQuery so the goldens are reproducible.
Future<void> _pumpOverlay(
  WidgetTester tester, {
  required ValueNotifier<OtaOverlayState> state,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(720, 1480);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: Stack(
          children: [
            const Center(
              child: Text(
                'App screen behind overlay',
                style: TextStyle(color: Colors.black45),
              ),
            ),
            OtaProgressOverlay(state: state),
          ],
        ),
      ),
    ),
  );
  // Let the spinner tick a few frames so the screenshot has a non-initial glyph.
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  group('Overlay goldens', () {
    testWidgets('idle (preparing)', (tester) async {
      final state = ValueNotifier(const OtaOverlayState());
      await _pumpOverlay(tester, state: state);
      await expectLater(
        find.byType(OtaProgressOverlay),
        matchesGoldenFile('goldens/overlay/01_idle.png'),
      );
    });

    testWidgets('downloading 0% (no fraction yet)', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.downloading,
          currentVersion: '1.0.0',
          targetVersion: '1.0.1',
          message: 'New onboarding flow',
        ),
      );
      await _pumpOverlay(tester, state: state);
      await expectLater(
        find.byType(OtaProgressOverlay),
        matchesGoldenFile('goldens/overlay/02_downloading_start.png'),
      );
    });

    testWidgets('downloading 50% (fraction known)', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.downloading,
          fraction: 0.50,
          currentVersion: '1.0.0',
          targetVersion: '1.0.1',
          message: 'New onboarding flow',
        ),
      );
      await _pumpOverlay(tester, state: state);
      await expectLater(
        find.byType(OtaProgressOverlay),
        matchesGoldenFile('goldens/overlay/03_downloading_mid.png'),
      );
    });

    testWidgets('verifying 85%', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.verifying,
          fraction: 0.85,
          currentVersion: '1.0.0',
          targetVersion: '1.0.1',
          message: 'Critical security fix',
        ),
      );
      await _pumpOverlay(tester, state: state);
      await expectLater(
        find.byType(OtaProgressOverlay),
        matchesGoldenFile('goldens/overlay/04_verifying.png'),
      );
    });

    testWidgets('error state with hint', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          hasError: true,
          errorText: 'MD5 mismatch: expected 414243…',
          errorHint: 'Close the app and reopen to retry.',
          currentVersion: '1.0.0',
          targetVersion: '1.0.1',
        ),
      );
      await _pumpOverlay(tester, state: state);
      await expectLater(
        find.byType(OtaProgressOverlay),
        matchesGoldenFile('goldens/overlay/05_error.png'),
      );
    });

    testWidgets('downloading 50% on dark theme', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.downloading,
          fraction: 0.50,
          currentVersion: '1.0.0',
          targetVersion: '1.0.1',
          message: 'New onboarding flow',
        ),
      );
      await _pumpOverlay(
        tester,
        state: state,
        theme: ThemeData.dark(useMaterial3: true),
      );
      await expectLater(
        find.byType(OtaProgressOverlay),
        matchesGoldenFile('goldens/overlay/06_dark.png'),
      );
    });
  });
}
