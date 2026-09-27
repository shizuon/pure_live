import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/utils/mobile_engine_policy.dart';
import 'package:pure_live/player/utils/player_consts.dart';

void main() {
  test('iOS IJK retains the BGRA pixel-buffer renderer format in both decode modes', () {
    for (final enabled in [false, true]) {
      final ios = MobileEnginePolicy.ijkPlayerOptions(TargetPlatform.iOS, enabled);
      expect(ios['overlay-format'], 'fcc-bgra');
      expect(ios['videotoolbox'], enabled ? 1 : 0);
      expect(ios, isNot(contains('mediacodec')));
      final android = MobileEnginePolicy.ijkPlayerOptions(TargetPlatform.android, enabled);
      expect(android['overlay-format'], 0x52474238);
      expect(android['mediacodec'], enabled ? 1 : 0);
      expect(android, isNot(contains('videotoolbox')));
    }
  });
  test('known unsupported AVPlayer live containers fail before native setup only on iOS', () {
    for (final source in ['https://cdn.test/live.FLV?token=x', 'rtmp://cdn.test/live', 'rtmps://cdn.test/live']) {
      expect(MobileEnginePolicy.isKnownUnsupportedAvPlayerSource(source, TargetPlatform.iOS), isTrue);
      expect(MobileEnginePolicy.isKnownUnsupportedAvPlayerSource(source, TargetPlatform.android), isFalse);
    }
    for (final source in ['https://cdn.test/a.m3u8', 'https://cdn.test/a.mp4', 'https://cdn.test/opaque?x=.flv']) {
      expect(MobileEnginePolicy.isKnownUnsupportedAvPlayerSource(source, TargetPlatform.iOS), isFalse);
    }
  });
  test('iOS label describes AVPlayer but preserves the stored exo key', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(PlayerConsts.names['exo'], 'player_avplayer');
    expect(PlayerConsts.getKeyByI18nKey('player_avplayer'), 'exo');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(PlayerConsts.names['exo'], 'player_exo');
  });
}
