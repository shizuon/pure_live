abstract interface class SyncCapablePlayer {
  Stream<Duration> get position;

  Stream<Duration> get bufferPosition;

  Duration get currentPosition;

  bool get isBufferingNow;

  bool get hasAudioTrack;

  Future<void> setPlaybackRate(double rate);
}
