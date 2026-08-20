import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/controllers/commentary_sync_controller.dart';
import 'package:pure_live/modules/live_play/service/stream_source_resolver.dart';
import 'package:pure_live/modules/live_play/states/commentary_sync_state.dart';
import 'package:pure_live/player/core/engine_fallback_manager.dart';
import 'package:pure_live/player/core/line_fallback_manager.dart';
import 'package:pure_live/player/core/player_manager.dart';
import 'package:pure_live/player/core/player_pool.dart';
import 'package:pure_live/player/core/preload_player_manager.dart';
import 'package:pure_live/player/interface/sync_capable_player.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/player/models/player_state.dart';
import 'package:rxdart/rxdart.dart';

void main() {
  test('calibration pauses the correct stream and restores primary volume', () async {
    final primary = _SyncPlayer(position: const Duration(seconds: 30));
    final companion = _SyncPlayer(position: const Duration(seconds: 27));
    final pool = PlayerPool(factory: (_) async => companion);
    final manager = _PlayerManager(primary: primary, pool: pool);
    final controller = CommentarySyncController(primaryManager: manager, playerPool: pool, resolver: const _Resolver());
    final videoRoom = LiveRoom(roomId: 'video', platform: 'test', nick: 'A');
    final audioRoom = LiveRoom(roomId: 'audio', platform: 'test', nick: 'B');

    await controller
        .activate(videoRoom: videoRoom, audioRoom: audioRoom, primaryVolume: 0.6)
        .timeout(const Duration(seconds: 5));

    expect(controller.state.value.status, CommentarySyncStatus.active);
    expect(companion.initializedAudioOnly, isFalse);
    expect(companion.sourceAudioOnly, isFalse);
    expect(controller.state.value.previewVisible, isTrue, reason: 'B video must be visible for timestamp calibration');
    expect(manager.lastVolume, 0);
    expect(companion.lastVolume, 0.6);

    await controller.adjustOffset(100);
    expect(companion.pauseCount, 1, reason: 'positive offset delays B');
    expect(primary.pauseCount, 0);

    await controller.adjustOffset(-200);
    expect(primary.pauseCount, 1, reason: 'negative offset advances B');
    expect(controller.state.value.offsetMs, -100);

    controller.finishCalibrationPreview();
    expect(controller.state.value.previewVisible, isFalse);
    expect(controller.state.value.offsetMs, -100);
    controller.showCalibrationPreview();
    expect(
      controller.state.value.previewVisible,
      isTrue,
      reason: 'calibration can be reopened without losing the offset',
    );
    expect(controller.state.value.offsetMs, -100);

    await controller.exit();
    expect(manager.lastVolume, 0.6);
    expect(companion.disposed, isTrue);

    await controller.dispose();
  }, timeout: const Timeout(Duration(seconds: 8)));

  test('exiting during crossfade cannot leave the primary stream muted', () async {
    final primary = _SyncPlayer(position: const Duration(seconds: 30));
    final companion = _SyncPlayer(position: const Duration(seconds: 27));
    final pool = PlayerPool(factory: (_) async => companion);
    final manager = _PlayerManager(primary: primary, pool: pool);
    final controller = CommentarySyncController(primaryManager: manager, playerPool: pool, resolver: const _Resolver());
    final activation = controller.activate(
      videoRoom: LiveRoom(roomId: 'video', platform: 'test'),
      audioRoom: LiveRoom(roomId: 'audio', platform: 'test'),
      primaryVolume: 0.75,
    );

    await Future<void>.delayed(const Duration(milliseconds: 2050));
    await controller.exit();
    await activation;

    expect(controller.state.value.status, CommentarySyncStatus.inactive);
    expect(manager.lastVolume, 0.75);
    expect(manager.mutedForReloads, isFalse);

    await controller.dispose();
  }, timeout: const Timeout(Duration(seconds: 8)));
}

class _Resolver extends StreamSourceResolver {
  const _Resolver();

  @override
  Future<ResolvedCommentarySource> resolveCommentary(LiveRoom selectedRoom) {
    final quality = LivePlayQuality(quality: '流畅');
    return Future.value(
      ResolvedCommentarySource(
        room: selectedRoom,
        candidates: [
          ResolvedStreamCandidate(
            room: selectedRoom,
            quality: quality,
            url: 'https://example.invalid/live.flv',
            playUrls: const ['https://example.invalid/live.flv'],
            headers: const {},
          ),
        ],
      ),
    );
  }
}

class _PlayerManager extends PlayerManager {
  _PlayerManager({required this.primary, required PlayerPool pool})
    : super(
        playerPool: pool,
        fallbackManager: EngineFallbackManager(
          defaultEngine: PlayerEngine.mediaKit,
          supportedEngines: const [PlayerEngine.mediaKit],
        ),
        preloadManager: PreloadPlayerManager(),
        lineManager: LineFallbackManager(),
      );

  final _SyncPlayer primary;
  double lastVolume = 1;
  bool mutedForReloads = false;

  @override
  UnifiedPlayer? get currentPlayer => primary;

  @override
  bool get isPlayingNow => primary.isPlayingNow;

  @override
  Stream<bool> get onLoading => primary.onLoading;

  @override
  Future<void> setVolume(double volume) async {
    lastVolume = volume;
    await primary.setVolume(volume);
  }

  @override
  Future<void> pause() => primary.pause();

  @override
  Future<void> resume() => primary.play();

  @override
  void setMutedForFutureReloads(bool muted) {
    mutedForReloads = muted;
  }
}

class _SyncPlayer implements UnifiedPlayer, SyncCapablePlayer {
  _SyncPlayer({required Duration position}) : _currentPosition = position;

  final Duration _currentPosition;
  final BehaviorSubject<bool> _playing = BehaviorSubject.seeded(true);
  final BehaviorSubject<bool> _loading = BehaviorSubject.seeded(false);
  int pauseCount = 0;
  double lastVolume = 1;
  bool disposed = false;
  bool? initializedAudioOnly;
  bool? sourceAudioOnly;

  @override
  Future<void> init({bool audioOnly = false}) async {
    initializedAudioOnly = audioOnly;
  }

  @override
  Future<void> setDataSource(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
    bool audioOnly = false,
    bool startMuted = false,
    bool force = false,
  }) async {
    sourceAudioOnly = audioOnly;
    _loading.add(false);
    _playing.add(true);
  }

  @override
  Future<void> play() async => _playing.add(true);

  @override
  Future<void> pause() async {
    pauseCount++;
    _playing.add(false);
  }

  @override
  Future<void> stop() => pause();

  @override
  Future<void> softStop() => pause();

  @override
  Future<void> hardDispose() async {
    disposed = true;
    await _playing.close();
    await _loading.close();
  }

  @override
  Future<void> setVolume(double volume) async => lastVolume = volume;

  @override
  Future<void> setAudioOnly(bool audioOnly) async {}

  @override
  Future<void> setPlaybackRate(double rate) async {}

  @override
  Widget getVideoWidget() => const SizedBox.shrink();

  @override
  bool get isInitialized => true;

  @override
  bool get isPlayingNow => _playing.value;

  @override
  bool get isReusable => false;

  @override
  bool get isBufferingNow => _loading.value;

  @override
  bool get hasAudioTrack => true;

  @override
  Duration get currentPosition => _currentPosition;

  @override
  Stream<Duration> get bufferPosition => Stream.value(_currentPosition);

  @override
  Stream<Duration> get position => Stream.value(_currentPosition);

  @override
  Stream<PlayerState> get onStateChanged => const Stream.empty();

  @override
  Stream<bool> get onPlaying => _playing.stream;

  @override
  Stream<PlayerException> get onError => const Stream.empty();

  @override
  Stream<bool> get onLoading => _loading.stream;

  @override
  Stream<bool> get onComplete => const Stream.empty();

  @override
  Stream<int?> get width => const Stream.empty();

  @override
  Stream<int?> get height => const Stream.empty();
}
