import 'package:flutter/material.dart';

/// Minimal accumulating-log + scrollable panel — for the example app only.
///
/// Usage:
/// ```dart
/// final log = LogController();
/// log.log('hello');
/// Expanded(child: LogPanel(controller: log));
/// ```
class LogController extends ChangeNotifier {
  final List<String> _lines = [];
  List<String> get lines => List.unmodifiable(_lines);

  /// Appends to the end: the UI shows lines top-to-bottom in time order, the first
  /// at the top and the newest at the bottom.
  void log(String msg) {
    _lines.add(msg);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}

class LogPanel extends StatefulWidget {
  const LogPanel({required this.controller, super.key});
  final LogController controller;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrollToBottom);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrollToBottom);
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Auto-scrolls to the bottom when the log overflows the viewport, keeping the
  /// newest line visible. `addPostFrameCallback` waits until ListView has laid out
  /// the new item before scrolling.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (_, _) {
        final lines = widget.controller.lines;
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(4),
          ),
          child: lines.isEmpty
              ? const Center(
                  child: Text(
                    '(logs will appear here)',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  itemCount: lines.length,
                  itemBuilder: (context, i) => Text(
                    lines[i],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
        );
      },
    );
  }
}
