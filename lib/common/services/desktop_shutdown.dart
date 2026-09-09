import 'dart:async';

/// One awaited shutdown transaction for window close and native Quit alike.
/// Never tear down the engine while SQLite/native player finalizers are pending.
class DesktopShutdown {
  DesktopShutdown({required this.detachViews, required this.closeResources});

  final Future<void> Function() detachViews;
  final Future<void> Function() closeResources;
  Future<void>? _pending;

  Future<void> run() => _pending ??= _run();

  Future<void> _run() async {
    try {
      await detachViews();
      await closeResources();
    } catch (_) {
      _pending = null;
      rethrow;
    }
  }

  static Future<void> Function()? beforeExit;
}
