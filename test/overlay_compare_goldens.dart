// Side-by-side goldens: v1 (old) vs v2 (new) overlay.
//
// Renders both variants under the same conditions so the user can compare
// the design differences visually. Run `flutter test --update-goldens` to
// regenerate; the goldens land in test/goldens/compare/.

import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Re-implementation of the pre-v2 overlay for visual comparison only.
/// Not exported, not used in production.
class _V1OtaOverlayState {
  final PatchApplyPhase? phase;
  final double? fraction;
  final String? message;
  final bool hasError;
  final String? errorText;
  final String? currentVersion;
  final String? targetVersion;
  const _V1OtaOverlayState({
    this.phase,
    this.fraction,
    this.message,
    this.hasError = false,
    this.errorText,
    this.currentVersion,
    this.targetVersion,
  });
}

const _v1Spinner = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

class _V1DotSpinner extends StatefulWidget {
  final Color color;
  const _V1DotSpinner({required this.color});
  @override
  State<_V1DotSpinner> createState() => _V1DotSpinnerState();
}

class _V1DotSpinnerState extends State<_V1DotSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _index = 0;
  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 800),
          )
          ..addListener(_tick)
          ..repeat();
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _index = (_index + 1) % _v1Spinner.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    _v1Spinner[_index],
    style: TextStyle(
      fontSize: 22,
      height: 1,
      fontWeight: FontWeight.bold,
      color: widget.color,
      fontFamily: 'monospace',
    ),
  );
}

class _V1Overlay extends StatelessWidget {
  final _V1OtaOverlayState state;
  const _V1Overlay({required this.state});

  static const Map<PatchApplyPhase, String> _phaseLabel = {
    PatchApplyPhase.downloading: 'Downloading update',
    PatchApplyPhase.verifying: 'Verifying signature',
    PatchApplyPhase.finalizing: 'Installing patch',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phaseText = state.hasError
        ? 'Update failed'
        : (state.phase != null
              ? _phaseLabel[state.phase]!
              : 'Preparing update');
    final pct = state.fraction;
    final pctText = pct != null ? '${(pct * 100).toStringAsFixed(0)}%' : null;
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _V1DotSpinner(
                    color: state.hasError ? scheme.error : scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      phaseText,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (pctText != null)
                    Text(
                      pctText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(
                    state.hasError ? scheme.error : scheme.primary,
                  ),
                ),
              ),
              if (state.message != null && state.message!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  state.message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
              if (state.hasError && state.errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.errorText!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders both overlays side by side under a shared MaterialApp.
class _Compare extends StatelessWidget {
  final _V1OtaOverlayState v1State;
  final OtaOverlayState v2State;
  const _Compare({required this.v1State, required this.v2State});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Center(
                      child: Text(
                        'v1 (old)',
                        style: TextStyle(fontSize: 12, color: Colors.black45),
                      ),
                    ),
                    _V1Overlay(state: v1State),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Center(
                      child: Text(
                        'v2 (new)',
                        style: TextStyle(fontSize: 12, color: Colors.black45),
                      ),
                    ),
                    OtaProgressOverlay(state: ValueNotifier(v2State)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

OtaOverlayState _v2FromV1(_V1OtaOverlayState v1) => OtaOverlayState(
  phase: v1.phase,
  fraction: v1.fraction,
  message: v1.message,
  hasError: v1.hasError,
  errorText: v1.errorText,
);

void main() {
  // Use a deterministic size so the goldens are reproducible across machines.
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1440, 720);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  testWidgets('compare downloading 0% (no fraction yet)', (tester) async {
    const v1 = _V1OtaOverlayState(
      phase: PatchApplyPhase.downloading,
      currentVersion: '1.0.0',
      targetVersion: '1.0.1',
      message: 'New onboarding flow',
    );
    final v2 = _v2FromV1(v1).copyWith(
      currentVersion: '1.0.0',
      targetVersion: '1.0.1',
      message: 'New onboarding flow',
    );
    await tester.pumpWidget(_Compare(v1State: v1, v2State: v2));
    await tester.pump(const Duration(milliseconds: 80));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/compare/01_downloading_0.png'),
    );
  });

  testWidgets('compare downloading 50% (fraction known)', (tester) async {
    const v1 = _V1OtaOverlayState(
      phase: PatchApplyPhase.downloading,
      fraction: 0.50,
      currentVersion: '1.0.0',
      targetVersion: '1.0.1',
      message: 'New onboarding flow',
    );
    final v2 = _v2FromV1(v1).copyWith(
      currentVersion: '1.0.0',
      targetVersion: '1.0.1',
      message: 'New onboarding flow',
    );
    await tester.pumpWidget(_Compare(v1State: v1, v2State: v2));
    await tester.pump(const Duration(milliseconds: 80));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/compare/02_downloading_50.png'),
    );
  });

  testWidgets('compare verifying 85%', (tester) async {
    const v1 = _V1OtaOverlayState(
      phase: PatchApplyPhase.verifying,
      fraction: 0.85,
      currentVersion: '1.0.0',
      targetVersion: '1.0.1',
      message: 'Critical security fix',
    );
    final v2 = _v2FromV1(v1).copyWith(
      currentVersion: '1.0.0',
      targetVersion: '1.0.1',
      message: 'Critical security fix',
    );
    await tester.pumpWidget(_Compare(v1State: v1, v2State: v2));
    await tester.pump(const Duration(milliseconds: 80));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/compare/03_verifying_85.png'),
    );
  });

  testWidgets('compare error state', (tester) async {
    const v1 = _V1OtaOverlayState(
      hasError: true,
      errorText: 'MD5 mismatch: expected 414243…',
      currentVersion: '1.0.0',
      targetVersion: '1.0.1',
    );
    final v2 = _v2FromV1(v1).copyWith(
      errorHint: 'Close the app and reopen to retry.',
      currentVersion: '1.0.0',
      targetVersion: '1.0.1',
    );
    await tester.pumpWidget(_Compare(v1State: v1, v2State: v2));
    await tester.pump(const Duration(milliseconds: 80));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/compare/04_error.png'),
    );
  });
}
