import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/service/commentary_buffer_policy.dart';

void main() {
  test('15 second calibration reserves delay plus a jitter margin, with a byte ceiling', () {
    expect(CommentaryBufferPolicy.prefetchSeconds(const Duration(seconds: 15)), 23);
    expect(CommentaryBufferPolicy.maximumForwardBytes, 128 * 1024 * 1024);
    expect(CommentaryBufferPolicy.prefetchSeconds(const Duration(hours: 1)), 53);
  });
  test('reversing offset retains the delay already accumulated in the other player', () {
    final first = CommentaryBufferPolicy.afterAdjustment(primaryMs: 0, commentaryMs: 0, deltaMs: -15000);
    final reverse = CommentaryBufferPolicy.afterAdjustment(
      primaryMs: first.primary,
      commentaryMs: first.commentary,
      deltaMs: 15000,
    );
    expect(reverse.primary, 15000);
    expect(reverse.commentary, 15000);
    expect(CommentaryBufferPolicy.fits(primaryMs: reverse.primary, commentaryMs: reverse.commentary), isTrue);
    expect(CommentaryBufferPolicy.fits(primaryMs: 46000, commentaryMs: 0), isFalse);
  });
  test('low or unknown buffer suppresses speedup; slowing down remains available', () {
    for (final buffer in [null, Duration.zero, const Duration(seconds: 3)]) {
      expect(CommentaryBufferPolicy.guardRate(1.02, buffer), 1);
      expect(CommentaryBufferPolicy.guardRate(.98, buffer), .98);
    }
    expect(CommentaryBufferPolicy.guardRate(1.02, const Duration(seconds: 5)), 1.02);
  });
}
