abstract interface class LiveAudioControlDelegate {
  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> setVolume(double volume);
}

/// Optional lifecycle callbacks for a coordinator that has to rebuild its
/// timing baseline when the primary stream is transparently reopened.
abstract interface class PrimaryPlaybackReloadDelegate {
  void markPrimaryReloading();

  Future<void> onPrimaryReady();
}
