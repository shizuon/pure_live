import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/get/get.dart' show Rx;
import 'package:pure_live/modules/live_play/states/commentary_overlay_layout.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/controllers/commentary_sync_controller.dart';
import 'package:pure_live/modules/live_play/service/stream_source_resolver.dart';
import 'package:pure_live/modules/live_play/states/commentary_sync_state.dart';
import 'package:pure_live/modules/live_play/widgets/commentary_video_overlay.dart';
import 'package:pure_live/player/core/engine_fallback_manager.dart';
import 'package:pure_live/player/core/line_fallback_manager.dart';
import 'package:pure_live/player/core/player_manager.dart';
import 'package:pure_live/player/core/player_pool.dart';
import 'package:pure_live/player/interface/sync_capable_player.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/player/models/player_state.dart';
import 'package:rxdart/rxdart.dart' show BehaviorSubject;

void main() {
  test('calibration pauses the correct stream and restores primary volume', () async {
    final primary = _SyncPlayer(position: const Duration(seconds: 30));
    final companion = _SyncPlayer(position: const Duration(seconds: 27));
    final pool = PlayerPool(factory: (_) async => companion);
    final manager = _PlayerManager(primary: primary, pool: pool);
    final controller = CommentarySyncController(
      primaryManager: manager,
      playerPool: pool,
      resolver: const _Resolver(),
      platformSupportProbe: () => true,
    );
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

    await controller.adjustOffset(10);
    expect(companion.pauseCount, 1, reason: 'positive offset delays B');
    expect(primary.pauseCount, 0);

    await controller.adjustOffset(-20);
    expect(primary.pauseCount, 1, reason: 'negative offset advances B');
    expect(controller.state.value.offsetMs, -10);

    await controller.finishCalibrationPreview();
    expect(controller.state.value.previewVisible, isFalse);
    expect(controller.state.value.offsetMs, -10);
    await controller.showCalibrationPreview();
    expect(
      controller.state.value.previewVisible,
      isTrue,
      reason: 'calibration can be reopened without losing the offset',
    );
    expect(controller.state.value.offsetMs, -10);

    await controller.beginOverlayCrop();
    expect(controller.state.value.previewVisible, isFalse);
    await controller.cancelOverlayCrop();
    expect(controller.state.value.previewVisible, isTrue);
    expect(controller.state.value.overlayEnabled, isFalse);

    await controller.beginOverlayCrop();
    await controller.confirmOverlayCrop(const Rect.fromLTWH(0.7, 0.6, 0.2, 0.3));
    expect(controller.state.value.overlayEnabled, isTrue);
    expect(controller.state.value.previewVisible, isFalse);
    expect(companion.audioOnlyModes.last, isFalse);
    await controller.showCalibrationPreview();
    await controller.finishCalibrationPreview();
    expect(companion.audioOnlyModes.last, isFalse, reason: 'finishing calibration must preserve the face overlay');
    expect(controller.state.value.offsetMs, -10);
    await controller.disableOverlay();
    expect(companion.audioOnlyModes.last, isTrue);
    expect(companion.lastVolume, 0.6, reason: 'closing the face must preserve B audio');

    // Rapid UI toggles must not drop the final video-enabled request.
    await Future.wait([
      controller.showCalibrationPreview(),
      controller.finishCalibrationPreview(),
      controller.showCalibrationPreview(),
    ]);
    expect(companion.audioOnlyModes.last, isFalse);

    await Future.wait([controller.exit(), controller.dispose(), controller.dispose()]);
    expect(manager.lastVolume, 0.6);
    expect(companion.disposed, isTrue);
    expect(controller.state.value.overlayEnabled, isFalse);
    expect(controller.state.value.overlayEditing, isFalse);

    await controller.exit(); // A late route close after application cleanup is harmless.
    await controller.dispose();
  }, timeout: const Timeout(Duration(seconds: 8)));

  test('reopening B keeps crop; replacing B clears it and releases old video', () async {
    final primary = _SyncPlayer(position: const Duration(seconds: 30));
    final companions = <_SyncPlayer>[];
    final pool = PlayerPool(
      factory: (_) async {
        final player = _SyncPlayer(position: const Duration(seconds: 27));
        companions.add(player);
        return player;
      },
    );
    final controller = CommentarySyncController(
      primaryManager: _PlayerManager(primary: primary, pool: pool),
      playerPool: pool,
      resolver: const _Resolver(),
      platformSupportProbe: () => true,
    );
    final videoRoom = LiveRoom(roomId: 'video', platform: 'test');
    await controller.activate(
      videoRoom: videoRoom,
      audioRoom: LiveRoom(roomId: 'audio', platform: 'test'),
      primaryVolume: 0.6,
    );
    const crop = Rect.fromLTWH(0.7, 0.6, 0.2, 0.3);
    await controller.beginOverlayCrop();
    await controller.confirmOverlayCrop(crop);
    await controller.resync(reopenPrimary: primary.play);
    await controller.finishCalibrationPreview();
    expect(controller.state.value.overlayEnabled, isTrue);
    expect(controller.state.value.overlayLayout.crop, crop);
    expect(companions.last.audioOnlyModes.last, isFalse);
    expect(companions.first.disposed, isTrue);
    await controller.activate(
      videoRoom: videoRoom,
      audioRoom: LiveRoom(roomId: 'another-audio', platform: 'test'),
      primaryVolume: 0.6,
    );
    expect(controller.state.value.overlayEnabled, isFalse);
    expect(controller.state.value.overlayLayout.crop, const Rect.fromLTWH(0, 0, 1, 1));
    await controller.dispose();
    expect(companions.every((player) => player.disposed), isTrue);
  }, timeout: const Timeout(Duration(seconds: 12)));

  testWidgets('crop, move, resize and hide chrome without hiding B video', (tester) async {
    const companion = _PreviewPlayer();
    // Playback/reconnect timing is covered by the controller tests above.
    // Mount an already-playing source here so pointer tests stay deterministic.
    final controller = _OverlayController(companion);
    addTearDown(controller.state.close);
    controller.state.value = const CommentarySyncState(status: CommentarySyncStatus.active);
    Future<void> show({bool controls = true}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              CommentaryVideoOverlay(
                sync: controller,
                controlsVisible: controls,
                controlsLocked: false,
                onInteraction: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await controller.beginOverlayCrop();
    await show();
    await tester.pumpAndSettle();
    final selection = find.byKey(const ValueKey('commentary-crop-selection'));
    expect(selection, findsOneWidget);
    final rect = tester.getRect(selection);
    await tester.dragFrom(rect.topLeft + const Offset(40, 40), const Offset(200, 150));
    await tester.pump();
    for (final handle in CropHandle.values) {
      expect(find.byKey(ValueKey('commentary-crop-handle-${handle.name}')), findsOneWidget);
    }
    await tester.drag(find.byKey(const ValueKey('commentary-crop-handle-right')), const Offset(30, 0));
    await tester.pump();
    expect(controller.state.value.overlayEnabled, isFalse, reason: 'adjustments require explicit confirmation');
    await tester.tap(find.text('覆盖到 A 画面'));
    await tester.pumpAndSettle();
    expect(controller.state.value.overlayEnabled, isTrue);
    final move = find.byKey(const ValueKey('commentary-overlay-move'));
    final before = tester.getRect(move);
    await tester.dragFrom(before.center, const Offset(-80, -50));
    await tester.pump();
    expect(tester.getRect(move).left, lessThan(before.left));
    final oldWidth = tester.getSize(move).width;
    await tester.drag(find.byKey(const ValueKey('commentary-overlay-resize')), const Offset(60, 20));
    await tester.pump();
    expect(controller.state.value.overlayLayout.widthFraction, greaterThan(0.25));
    expect(tester.getSize(move).width, greaterThan(oldWidth));
    // Repeat both reparenting directions with an actual single-subscription
    // stream, as created by MediaKitAdapter.getVideoWidget (not a bare box).
    await controller.beginOverlayCrop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('覆盖到 A 画面'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await show(controls: false);
    await tester.pumpAndSettle();
    expect(move, findsOneWidget);
    expect(find.byTooltip('重新选区'), findsNothing);
    controller.state.value = controller.state.value.copyWith(status: CommentarySyncStatus.reconnecting);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('test-companion-video')),
      findsNothing,
      reason: 'detach the old native surface while the companion is replaced',
    );
    controller.state.value = controller.state.value.copyWith(status: CommentarySyncStatus.active);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('test-companion-video')), findsOneWidget);
    await controller.showCalibrationPreview();
    await tester.pump();
    expect(move, findsNothing, reason: 'the preview owns B rendering while calibrating');
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('exiting during crossfade cannot leave the primary stream muted', () async {
    final primary = _SyncPlayer(position: const Duration(seconds: 30));
    final companion = _SyncPlayer(position: const Duration(seconds: 27));
    final pool = PlayerPool(factory: (_) async => companion);
    final manager = _PlayerManager(primary: primary, pool: pool);
    final controller = CommentarySyncController(
      primaryManager: manager,
      playerPool: pool,
      resolver: const _Resolver(),
      platformSupportProbe: () => true,
    );
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

class _OverlayController implements CommentarySyncController {
  _OverlayController(this.preview);
  final UnifiedPlayer preview;
  @override
  UnifiedPlayer get companionPreviewPlayer => preview;
  @override
  final state = Rx<CommentarySyncState>(const CommentarySyncState());
  @override
  Future<void> beginOverlayCrop() async {
    state.value = state.value.copyWith(overlayEditing: true, previewVisible: false);
  }

  @override
  Future<void> cancelOverlayCrop() async {
    state.value = state.value.copyWith(overlayEditing: false);
  }

  @override
  Future<void> confirmOverlayCrop(Rect crop) async {
    state.value = state.value.copyWith(
      overlayEditing: false,
      overlayEnabled: true,
      overlayLayout: state.value.overlayLayout.copyWith(crop: crop),
    );
  }

  @override
  Future<void> disableOverlay() async {
    state.value = state.value.copyWith(overlayEnabled: false);
  }

  @override
  void updateOverlayLayout(CommentaryOverlayLayout layout) {
    state.value = state.value.copyWith(overlayLayout: layout);
  }

  @override
  Future<void> showCalibrationPreview() async {
    state.value = state.value.copyWith(previewVisible: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Rendering-only fixture. Any unexpected playback call fails through
/// noSuchMethod; playback and disposal are tested with _SyncPlayer separately.
class _PreviewPlayer implements UnifiedPlayer {
  const _PreviewPlayer();
  @override
  Widget getVideoWidget(BoxFit fit) => StreamBuilder<int>(
    stream: Stream.value(1920),
    builder: (_, _) => const SizedBox.expand(key: ValueKey('test-companion-video')),
  );
  @override
  Stream<int?> get width => Stream.value(1920);
  @override
  Stream<int?> get height => Stream.value(1080);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
        fallbackManager: EngineFallbackManager(
          defaultEngine: PlayerEngine.mediaKit,
          supportedEngines: const [PlayerEngine.mediaKit],
        ),
        lineManager: LineFallbackManager(),
        playerCreator: (_) async => primary,
        audioModeServiceSync: (_, _) async {},
        audioSessionStart: (_) async {},
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
  Stream<bool> get onPlaying => primary.onPlaying;

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
  final List<bool> audioOnlyModes = [];

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
  Future<void> setAudioOnly(bool audioOnly) async {
    audioOnlyModes.add(audioOnly);
  }

  @override
  Future<void> setPlaybackRate(double rate) async {}

  @override
  Widget getVideoWidget(BoxFit fit) => const SizedBox.expand(key: ValueKey('test-companion-video'));

  @override
  PlayerEngine get engine => PlayerEngine.mediaKit;

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
  Stream<int?> get width => Stream.value(1920);

  @override
  Stream<int?> get height => Stream.value(1080);
}
