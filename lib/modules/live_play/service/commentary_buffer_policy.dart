class CommentaryBufferPolicy {
  static const int activationMs = 5000;
  static const int maximumRetainedMs = 45000;
  static const int reserveSeconds = 8;
  static const int maximumForwardBytes = 128 * 1024 * 1024;
  static const Duration speedupMinimum = Duration(seconds: 4);

  /// Offset reversals pause the opposite player; they do not discard already
  /// cached content. Track both cumulative holds, not just abs(offset).
  static ({int primary, int commentary}) afterAdjustment({
    required int primaryMs,
    required int commentaryMs,
    required int deltaMs,
  }) => (primary: primaryMs + (deltaMs < 0 ? -deltaMs : 0), commentary: commentaryMs + (deltaMs > 0 ? deltaMs : 0));

  static bool fits({required int primaryMs, required int commentaryMs}) =>
      primaryMs <= maximumRetainedMs && commentaryMs <= maximumRetainedMs;

  static int prefetchSeconds(Duration retainedDelay) =>
      (retainedDelay.inMilliseconds.clamp(0, maximumRetainedMs) / 1000).ceil() + reserveSeconds;

  static double guardRate(double rate, Duration? headroom) =>
      rate > 1 && (headroom == null || headroom < speedupMinimum) ? 1 : rate;
}
