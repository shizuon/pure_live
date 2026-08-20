class CommentarySyncMath {
  const CommentarySyncMath._();

  static int clampOffset(int offsetMs, {int minimum = -30000, int maximum = 30000}) {
    return offsetMs.clamp(minimum, maximum).toInt();
  }

  static double desiredGapMs({required double baselineGapMs, required int offsetMs}) {
    return baselineGapMs - offsetMs;
  }

  static double correctionRate({required double errorMs, required int consecutiveSamples}) {
    if (errorMs.abs() <= 150 || consecutiveSamples < 3) return 1;
    return errorMs > 0 ? 0.98 : 1.02;
  }
}
