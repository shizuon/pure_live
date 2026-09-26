/// Optional native capability. Does not seek, reload, or change playback
/// position; only adjusts bounded packet prefetch while keeping the same URL.
abstract interface class CommentaryBufferControl {
  Future<void> reserveSyncBuffer(Duration retainedDelay);
  Future<void> restoreSyncBuffer();

  /// Approximate demuxer headroom, not an exact network or content clock.
  /// Null means unsupported/unavailable and must never be treated as zero.
  Future<Duration?> readBufferedAhead();
}
