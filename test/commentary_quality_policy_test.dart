import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/service/commentary_quality_policy.dart';

void main() {
  List<LivePlayQuality> qualities(List<String> labels) => [
    for (var i = 0; i < labels.length; i++) LivePlayQuality(quality: labels[i], id: i),
  ];
  test('prefer readable 4M before calibration, then higher tiers before low fallbacks', () {
    final ordered = CommentaryQualityPolicy.order(qualities(['蓝光30M', '蓝光8M', '蓝光4M', '超清', '流畅']));
    expect(ordered.map((q) => q.quality), ['蓝光4M', '蓝光8M', '蓝光30M', '超清', '流畅']);
  });
  test('8M is preferred when no 4M exists; other platforms use readable labels', () {
    expect(CommentaryQualityPolicy.order(qualities(['蓝光20M', '蓝光8M', '蓝光2M'])).first.quality, '蓝光8M');
    expect(CommentaryQualityPolicy.order(qualities(['1080p60', '720p', '480p'])).first.quality, '1080p60');
    expect(CommentaryQualityPolicy.order(qualities(['原画', '超清', '流畅'])).first.quality, '原画');
  });
  test('platform ids are opaque; user choice overrides the default without changing ids', () {
    final input = [
      LivePlayQuality(quality: '原画', id: 0),
      LivePlayQuality(quality: '高清', id: 8),
      LivePlayQuality(quality: '流畅', id: 4),
    ];
    expect(CommentaryQualityPolicy.order(input).first.selectionId, 0);
    expect(CommentaryQualityPolicy.order(input, preferredId: '8').first.selectionId, 8);
    expect(CommentaryQualityPolicy.order(input, preferredId: 'expired').first.selectionId, 0);
  });
}
