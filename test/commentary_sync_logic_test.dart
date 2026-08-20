import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/service/commentary_sync_math.dart';
import 'package:pure_live/modules/live_play/service/commentary_platform_support.dart';
import 'package:pure_live/modules/live_play/service/stream_source_resolver.dart';
import 'package:pure_live/modules/live_play/states/commentary_sync_state.dart';
import 'package:pure_live/modules/live_play/widgets/commentary_sync_widgets.dart';
import 'package:pure_live/player/adapters/media_kit_adapter.dart';

void main() {
  group('commentary synchronization math', () {
    test('clamps session offset to thirty seconds', () {
      expect(CommentarySyncMath.clampOffset(50000), 30000);
      expect(CommentarySyncMath.clampOffset(-50000), -30000);
      expect(CommentarySyncMath.clampOffset(1200), 1200);
    });

    test('positive offset means commentary audio is later', () {
      expect(CommentarySyncMath.desiredGapMs(baselineGapMs: 250, offsetMs: 100), 150);
      expect(CommentarySyncMath.desiredGapMs(baselineGapMs: 250, offsetMs: -100), 350);
    });

    test('drift correction waits for three samples and chooses direction', () {
      expect(CommentarySyncMath.correctionRate(errorMs: 400, consecutiveSamples: 2), 1);
      expect(CommentarySyncMath.correctionRate(errorMs: 400, consecutiveSamples: 3), 0.98);
      expect(CommentarySyncMath.correctionRate(errorMs: -400, consecutiveSamples: 3), 1.02);
      expect(CommentarySyncMath.correctionRate(errorMs: 100, consecutiveSamples: 3), 1);
    });
  });

  test('commentary qualities are attempted from lowest to highest', () {
    final ordered = StreamSourceResolver.lowestQualityFirst([
      LivePlayQuality(quality: '原画'),
      LivePlayQuality(quality: '高清'),
      LivePlayQuality(quality: '流畅'),
    ]);
    expect(ordered.map((quality) => quality.quality), ['流畅', '高清', '原画']);
  });

  test('a failed low quality still falls back to higher qualities', () async {
    final room = LiveRoom(roomId: 'b', platform: 'test');
    final candidates = await StreamSourceResolver.buildCandidates(
      room: room,
      qualities: [
        LivePlayQuality(quality: '原画'),
        LivePlayQuality(quality: '流畅'),
      ],
      headers: const {},
      getPlayUrls: (quality) async {
        if (quality.quality == '流畅') throw StateError('expired');
        return ['high-a', 'high-b'];
      },
    );
    expect(candidates.map((candidate) => candidate.url), ['high-a', 'high-b']);
  });

  test('error state stays engaged until the user exits dual stream', () {
    const state = CommentarySyncState(status: CommentarySyncStatus.error);
    expect(state.isEngaged, isTrue);
    expect(state.isActive, isFalse);
  });

  test('ten millisecond offsets remain visible instead of rounding to zero', () {
    expect(formatCommentaryOffset(10), '+10ms');
    expect(formatCommentaryOffset(-10), '-10ms');
    expect(formatCommentaryOffset(100), '+0.1s');
    expect(formatCommentaryOffset(1010), '+1.01s');
  });

  test('migration allow-list includes macOS, Windows and iOS only', () {
    expect(CommentaryPlatformSupport.supports(macOS: true, windows: false, iOS: false), isTrue);
    expect(CommentaryPlatformSupport.supports(macOS: false, windows: true, iOS: false), isTrue);
    expect(CommentaryPlatformSupport.supports(macOS: false, windows: false, iOS: true), isTrue);
    expect(CommentaryPlatformSupport.supports(macOS: false, windows: false, iOS: false), isFalse);
  });

  test('placeholder media tracks are not treated as a real audio track', () {
    expect(MediaKitAdapter.containsPlayableAudioTrackIds(['auto', 'no']), isFalse);
    expect(MediaKitAdapter.containsPlayableAudioTrackIds(['auto', '1', 'no']), isTrue);
  });
}
