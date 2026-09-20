import 'dart:async';

enum LiveRecoveryResult { reopened, retry, offline, cancelled }

/// Owns one live session's retry budget, independently of native player events.
/// A source can report both an error and EOF; neither is a second retry while
/// the same recovery is pending. Only sustained playback resets the budget.
class LivePlaybackRecovery {
  LivePlaybackRecovery({
    required this.reopen,
    required this.onExhausted,
    this.delays = const [Duration(seconds: 1), Duration(seconds: 3), Duration(seconds: 8)],
    this.stableWindow = const Duration(seconds: 30),
  });

  final Future<LiveRecoveryResult> Function(bool Function() isCurrent) reopen;
  final void Function(bool offline) onExhausted;
  final List<Duration> delays;
  final Duration stableWindow;
  Timer? _retryTimer;
  Timer? _stableTimer;
  int _generation = 0;
  int _attempts = 0;
  bool _enabled = false;
  bool _wanted = false;
  bool _started = false;
  bool _playing = false;
  bool _buffering = false;
  bool _running = false;
  bool _failedDuringAttempt = false;
  bool _exhausted = false;

  bool get isRecovering => _running || _retryTimer != null;
  int get attempt => _attempts;

  void startSession({required bool enabled}) {
    cancel();
    _enabled = enabled;
    _wanted = true;
    _started = false;
    _playing = false;
    _buffering = false;
    _attempts = 0;
    _exhausted = false;
  }

  void setWanted(bool wanted) {
    _wanted = wanted;
    if (!wanted) cancel();
  }

  void observe({bool? playing, bool? buffering}) {
    if (playing != null) {
      _playing = playing;
      if (playing) _started = true;
    }
    if (buffering != null) _buffering = buffering;
    _updateStableTimer();
  }

  void _updateStableTimer() {
    if (!_enabled || !_wanted || !_playing || _buffering || isRecovering || _exhausted || _attempts == 0) {
      _stableTimer?.cancel();
      _stableTimer = null;
      return;
    }
    _stableTimer ??= Timer(stableWindow, () {
      _stableTimer = null;
      _attempts = 0;
    });
  }

  /// Returns false for initial-open failures, recordings and user-paused rooms.
  /// Once handled here, a failure must not also trigger cached-line/engine
  /// fallback in a competing coordinator.
  bool request() {
    if (!_enabled || !_wanted || !_started) return false;
    _stableTimer?.cancel();
    _stableTimer = null;
    if (_exhausted || _retryTimer != null) return true;
    if (_running) {
      _failedDuringAttempt = true;
      return true;
    }
    _schedule();
    return true;
  }

  void _schedule() {
    if (_attempts >= delays.length) {
      _exhausted = true;
      onExhausted(false);
      return;
    }
    final generation = _generation;
    _retryTimer = Timer(delays[_attempts++], () {
      _retryTimer = null;
      unawaited(_run(generation));
    });
  }

  Future<void> _run(int generation) async {
    bool isCurrent() => generation == _generation && _enabled && _wanted;
    if (!isCurrent()) return;
    _running = true;
    _failedDuringAttempt = false;
    var result = LiveRecoveryResult.retry;
    try {
      result = await reopen(isCurrent);
    } catch (_) {
      // The owner publishes a single terminal error after the bounded budget.
    }
    if (!isCurrent()) return;
    _running = false;
    if (result == LiveRecoveryResult.cancelled) return;
    if (result == LiveRecoveryResult.offline) {
      _exhausted = true;
      onExhausted(true);
    } else if (result == LiveRecoveryResult.retry || _failedDuringAttempt) {
      _schedule();
    } else {
      _updateStableTimer();
    }
  }

  /// Fences late HTTP results as well as scheduled retries. Does not dispose
  /// the owner or mutate native playback, so a new session may start at once.
  void cancel() {
    _generation++;
    _retryTimer?.cancel();
    _stableTimer?.cancel();
    _retryTimer = null;
    _stableTimer = null;
    _running = false;
  }
}
