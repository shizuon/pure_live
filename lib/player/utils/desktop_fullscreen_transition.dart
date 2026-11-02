import 'dart:async';

import 'package:window_manager/window_manager.dart';

/// NSWindow's method-channel reply precedes its Space animation. Geometry may
/// only be changed after the native completion event, not after an arbitrary
/// delay. Register first so even synchronous Windows events cannot be lost.
Future<void> setDesktopFullScreen(bool value, {bool waitForEvent = false}) async {
  if (await windowManager.isFullScreen() == value) return;
  if (!waitForEvent) {
    await windowManager.setFullScreen(value);
    return;
  }
  final listener = _FullscreenCompletion(value);
  windowManager.addListener(listener);
  try {
    await windowManager.setFullScreen(value);
    await listener.completed.future.timeout(const Duration(seconds: 5));
  } finally {
    windowManager.removeListener(listener);
  }
}

class _FullscreenCompletion with WindowListener {
  _FullscreenCompletion(this.fullscreen);
  final bool fullscreen;
  final completed = Completer<void>();

  @override
  void onWindowEvent(String eventName) {
    final expected = fullscreen ? 'enter-full-screen' : 'leave-full-screen';
    if (eventName == expected && !completed.isCompleted) completed.complete();
  }
}
