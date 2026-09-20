import 'dart:async';

enum PlaybackInterruption { pause, duck }

/// Serializes OS interruption events while preserving newer user commands.
/// Command revisions are advanced by the same delegate used by the UI, not
/// inferred from decoder events (which also occur during calibration).
class AudioInterruptionRecovery {
  AudioInterruptionRecovery({
    required this.isPlaying,
    required this.volume,
    required this.transportRevision,
    required this.volumeRevision,
    required this.pause,
    required this.play,
    required this.setVolume,
  });

  final bool Function() isPlaying;
  final double Function() volume;
  final int Function() transportRevision;
  final int Function() volumeRevision;
  final Future<void> Function() pause;
  final Future<void> Function() play;
  final Future<void> Function(double) setVolume;
  Future<void> _tail = Future.value();
  int _generation = 0;
  int _pauseDepth = 0;
  int _duckDepth = 0;
  int? _resumeRevision;
  int? _restoreVolumeRevision;
  double? _restoreVolume;

  Future<void> handle(PlaybackInterruption type, {required bool begin}) {
    final generation = _generation;
    final task = _tail.then((_) async {
      if (generation != _generation) return;
      if (type == PlaybackInterruption.pause) {
        if (begin) {
          if (_pauseDepth++ != 0) return;
          if (!isPlaying()) return;
          _resumeRevision = transportRevision() + 1;
          await pause();
        } else {
          if (_pauseDepth == 0 || --_pauseDepth != 0) return;
          final expected = _resumeRevision;
          _resumeRevision = null;
          if (expected != null && expected == transportRevision()) await play();
        }
      } else if (begin) {
        if (_duckDepth++ != 0) return;
        _restoreVolume = volume();
        _restoreVolumeRevision = volumeRevision() + 1;
        await setVolume(_restoreVolume! * .2);
      } else {
        if (_duckDepth == 0 || --_duckDepth != 0) return;
        final expected = _restoreVolumeRevision;
        final previousVolume = _restoreVolume;
        _restoreVolumeRevision = null;
        _restoreVolume = null;
        if (expected != null && expected == volumeRevision() && previousVolume != null) {
          await setVolume(previousVolume);
        }
      }
    });
    _tail = task.then<void>((_) {}, onError: (_, _) {});
    return task;
  }

  void reset() {
    _generation++;
    _pauseDepth = 0;
    _duckDepth = 0;
    _resumeRevision = null;
    _restoreVolumeRevision = null;
    _restoreVolume = null;
  }
}
