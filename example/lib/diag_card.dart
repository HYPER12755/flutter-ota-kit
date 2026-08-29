import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';

/// A read-only card showing the last cold-start diagnostic — renders the result of
/// `FlutterPatcher.lastBootDiagnostic` into a UI the app can read at a glance,
/// instead of staring at logcat during on-device debugging.
///
/// Visual status encoding:
/// - green ✅: patched / noPatch (healthy)
/// - red ❌: droppedSignatureInvalid / droppedCircuitBreaker (strong alert)
/// - yellow ⚠️: other dropped / hook failure (gentle reminder)
class DiagCard extends StatefulWidget {
  const DiagCard({super.key});

  /// Lets external code (e.g. right after an apply / rollback) trigger the card to
  /// re-fetch diagnostics. Note: `lastBootDiagnostic` reflects the **last cold
  /// start** — it won't change immediately after apply; but re-reading fields like
  /// `app vc` is harmless and gives a visual "I clicked" refresh.
  static void refresh() => _refreshTick.value++;

  static final ValueNotifier<int> _refreshTick = ValueNotifier(0);

  @override
  State<DiagCard> createState() => _DiagCardState();
}

class _DiagCardState extends State<DiagCard> {
  PatchBootDiagnostic? _diag;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    DiagCard._refreshTick.addListener(_refresh);
  }

  @override
  void dispose() {
    DiagCard._refreshTick.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final diag = await FlutterPatcher.lastBootDiagnostic;
    if (!mounted) return;
    setState(() {
      _diag = diag;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, icon, title) = _visualFor(_diag, scheme);

    return Card(
      color: bg,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Last boot',
                        style: TextStyle(
                          fontSize: 12,
                          color: fg.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: _loading ? null : _refresh,
                        child: Icon(
                          Icons.refresh,
                          size: 16,
                          color: fg.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  ..._detailLines(_diag).map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        line,
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static (Color, Color, IconData, String) _visualFor(
    PatchBootDiagnostic? d,
    ColorScheme scheme,
  ) {
    if (d == null) {
      return (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.help_outline,
        'no diagnostic recorded yet',
      );
    }
    switch (d.status) {
      case PatchBootStatus.patched:
        return (
          Colors.green.shade50,
          Colors.green.shade900,
          Icons.check_circle,
          'patched${d.patchVersion != null ? " (v=${d.patchVersion})" : ""}',
        );
      case PatchBootStatus.noPatch:
        return (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.info_outline,
          'noPatch (built-in libapp.so)',
        );
      case PatchBootStatus.droppedSignatureInvalid:
      case PatchBootStatus.droppedCircuitBreaker:
        return (
          Colors.red.shade50,
          Colors.red.shade900,
          Icons.error,
          d.status.name,
        );
      default:
        return (
          Colors.orange.shade50,
          Colors.orange.shade900,
          Icons.warning_amber,
          d.status.name,
        );
    }
  }

  static List<String> _detailLines(PatchBootDiagnostic? d) {
    if (d == null) return const [];
    final lines = <String>[];
    // When versionCode mismatches, both values are meaningful; in other cases only
    // appVersionCode is present, and showing it alone is clearer than a half-empty
    // "patch vc=?, app vc=1" hint.
    if (d.patchTargetVersionCode != null && d.appVersionCode != null) {
      lines.add(
        'patch vc=${d.patchTargetVersionCode}, app vc=${d.appVersionCode}',
      );
    } else if (d.appVersionCode != null) {
      lines.add('app vc=${d.appVersionCode}');
    }
    if (d.crashCount != null) lines.add('crashCount=${d.crashCount}');
    if (d.attemptedLoaderFields != null &&
        d.attemptedLoaderFields!.isNotEmpty) {
      lines.add('triedFields=${d.attemptedLoaderFields!.join(",")}');
    }
    if (d.message != null && d.message!.isNotEmpty) {
      lines.add(d.message!);
    }
    return lines;
  }
}
