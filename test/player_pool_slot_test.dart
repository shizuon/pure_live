import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/player/core/player_pool.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/player/models/player_slot.dart';
import 'package:pure_live/player/models/player_state.dart';

void main() {
  test('player pool keeps main and commentary players in separate slots', () async {
    var factoryCalls = 0;
    final pool = PlayerPool(
      factory: (_) async {
        factoryCalls++;
        return _FakePlayer();
      },
    );

    final main = await pool.getPlayer(PlayerEngine.mediaKit);
    final commentary = await pool.getPlayer(PlayerEngine.mediaKit, slot: PlayerSlot.commentaryAudio, audioOnly: true);

    expect(main, isNot(same(commentary)));
    expect(factoryCalls, 2);
    expect(await pool.getPlayer(PlayerEngine.mediaKit), same(main));

    await pool.removeFromCache(PlayerEngine.mediaKit, slot: PlayerSlot.commentaryAudio);
    expect((commentary as _FakePlayer).disposed, isTrue);
    expect(pool.cachedPlayer(PlayerEngine.mediaKit, PlayerSlot.mainVideo), same(main));
  });
}

class _FakePlayer implements UnifiedPlayer {
  bool disposed = false;
  bool initialized = false;

  @override
  Future<void> hardDispose() async => disposed = true;

  @override
  Future<void> init({bool audioOnly = false}) async => initialized = true;

  @override
  bool get isInitialized => initialized;

  @override
  bool get isPlayingNow => false;

  @override
  bool get isReusable => true;

  @override
  Stream<bool> get onComplete => const Stream.empty();

  @override
  Stream<PlayerException> get onError => const Stream.empty();

  @override
  Stream<bool> get onLoading => const Stream.empty();

  @override
  Stream<bool> get onPlaying => const Stream.empty();

  @override
  Stream<PlayerState> get onStateChanged => const Stream.empty();

  @override
  Stream<int?> get height => const Stream.empty();

  @override
  Stream<int?> get width => const Stream.empty();

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> setDataSource(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
    bool audioOnly = false,
    bool startMuted = false,
    bool force = false,
  }) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setAudioOnly(bool audioOnly) async {}

  @override
  Future<void> softStop() async {}

  @override
  Future<void> stop() async {}

  @override
  Widget getVideoWidget() => const SizedBox.shrink();
}
