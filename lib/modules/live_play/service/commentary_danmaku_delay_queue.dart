import 'dart:async';
import 'dart:collection';

typedef CommentaryDanmakuTimerFactory = Timer Function(Duration duration, void Function() callback);

/// Delays commentary-room danmaku by the positive part of the A/B offset.
///
/// A negative offset asks the commentary stream to lead the primary stream.
/// A websocket message cannot be displayed before it has arrived, so negative
/// offsets intentionally resolve to zero delay.
class CommentaryDanmakuDelayQueue<T> {
  CommentaryDanmakuDelayQueue({
    required this.onEmit,
    DateTime Function()? now,
    CommentaryDanmakuTimerFactory? timerFactory,
    this.maxPendingMessages = 5000,
  }) : _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new;

  final void Function(T message) onEmit;
  final DateTime Function() _now;
  final CommentaryDanmakuTimerFactory _timerFactory;
  final int maxPendingMessages;

  final Queue<_PendingDanmaku<T>> _pending = Queue<_PendingDanmaku<T>>();
  Timer? _timer;
  int _delayMs = 0;
  bool _disposed = false;

  int get delayMs => _delayMs;
  int get pendingCount => _pending.length;

  static int effectiveDelayForOffset(int offsetMs) => offsetMs > 0 ? offsetMs : 0;

  void updateOffset(int offsetMs) {
    if (_disposed) return;
    final delay = effectiveDelayForOffset(offsetMs);
    if (_delayMs == delay) return;
    _delayMs = delay;
    _scheduleNext();
  }

  void add(T message) {
    if (_disposed) return;
    if (_delayMs == 0) {
      onEmit(message);
      return;
    }
    if (_pending.length >= maxPendingMessages) {
      _pending.removeFirst();
    }
    _pending.addLast(_PendingDanmaku(message: message, receivedAt: _now()));
    _scheduleNext();
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty || _disposed) return;

    _drainDueMessages();
    if (_pending.isEmpty || _disposed) return;

    final dueAt = _pending.first.receivedAt.add(Duration(milliseconds: _delayMs));
    final remaining = dueAt.difference(_now());
    _timer = _timerFactory(remaining.isNegative ? Duration.zero : remaining, _handleTimer);
  }

  void _handleTimer() {
    _timer = null;
    if (_disposed) return;
    _drainDueMessages();
    _scheduleNext();
  }

  void _drainDueMessages() {
    final now = _now();
    while (_pending.isNotEmpty) {
      final dueAt = _pending.first.receivedAt.add(Duration(milliseconds: _delayMs));
      if (dueAt.isAfter(now)) break;
      onEmit(_pending.removeFirst().message);
    }
  }
}

class _PendingDanmaku<T> {
  const _PendingDanmaku({required this.message, required this.receivedAt});

  final T message;
  final DateTime receivedAt;
}
