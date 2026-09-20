abstract interface class LiveAudioControlDelegate {
  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> setVolume(double volume);
}

/// Session state differs from the main decoder while calibration temporarily
/// holds one stream. Revisions let OS interruptions respect newer user input.
abstract interface class LiveAudioSessionState {
  bool get sessionPlaying;
  Stream<bool> get sessionPlayingStream;
  double get sessionVolume;
  int get transportRevision;
  int get volumeRevision;
}

/// Optional lifecycle callbacks for a coordinator that has to rebuild its
/// timing baseline when the primary stream is transparently reopened.
abstract interface class PrimaryPlaybackReloadDelegate {
  void markPrimaryReloading();

  Future<void> onPrimaryReady();
}
