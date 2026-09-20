import 'dart:async';

/// Coordinates the *session*, not individual decoder playing events. The
/// owner forwards app visibility/PiP changes; paused calibration is not a user
/// pause. This class deliberately contains no platform calls for deterministic
/// ordering and cancellation tests.
class MobileCommentaryLifecycle {
  MobileCommentaryLifecycle({
    required this.engaged,
    required this.sessionId,
    required this.isPlaying,
    required this.transportRevision,
    required this.pause,
    required this.play,
    required this.setVideoVisible,
  });

  final bool Function() engaged;
  final int Function() sessionId;
  final bool Function() isPlaying;
  final int Function() transportRevision;
  final Future<void> Function() pause;
  final Future<void> Function() play;
  final Future<void> Function(bool) setVideoVisible;
  Future<void> _tail = Future.value();
  int _request = 0;
  int? _ownedSession;
  int? _resumeRevision;
  bool _videoHidden = false;
  bool _disposed = false;

  Future<void> update({required bool visible, required bool inPip, required bool allowBackground}) {
    final request = ++_request;
    final session = sessionId();
    final videoVisible = visible || inPip;
    bool current() => !_disposed && request == _request && session == sessionId() && engaged();
    final work = _tail.then((_) async {
      if (!current()) return;
      if (_ownedSession != session) {
        _ownedSession = session;
        _resumeRevision = null;
        _videoHidden = false;
      }
      if (!videoVisible && !allowBackground && _resumeRevision == null && isPlaying()) {
        // Set before awaiting so a newer user command can supersede it.
        _resumeRevision = transportRevision() + 1;
        await pause();
        if (!current()) return;
      }
      if (_videoHidden == videoVisible) {
        await setVideoVisible(videoVisible);
        // Keep actual completed resource state even if a newer visibility
        // event arrived during native work; the next queued event reverses it.
        if (session == sessionId()) _videoHidden = !videoVisible;
        if (!current()) return;
      }
      if (videoVisible || allowBackground) {
        final revision = _resumeRevision;
        _resumeRevision = null;
        if (revision != null && revision == transportRevision()) await play();
      }
    });
    _tail = work.then<void>((_) {}, onError: (_, _) {});
    return work;
  }

  Future<void> dispose() async {
    _disposed = true;
    _request++;
    _resumeRevision = null;
    await _tail;
  }
}
