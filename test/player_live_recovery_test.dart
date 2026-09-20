import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/get/get.dart' hide VoidCallback;
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/player/core/engine_fallback_manager.dart';
import 'package:pure_live/player/core/line_fallback_manager.dart';
import 'package:pure_live/player/core/live_audio_control_delegate.dart';
import 'package:pure_live/player/core/live_source_refresher.dart';
import 'package:pure_live/player/core/player_manager.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';
import 'package:pure_live/player/interface/sync_capable_player.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/player/models/player_error_type.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/player/models/player_state.dart';
import 'package:rxdart/rxdart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
    Get.put(GlobalPlayerState());
  });
  tearDown(Get.reset);

  test('commentary uses MediaKit across reloads and restores the single-stream engine after release', () async {
    final created = <_Player>[];
    final manager = PlayerManager(
      fallbackManager: EngineFallbackManager(defaultEngine: PlayerEngine.fijk, supportedEngines: PlayerEngine.values),
      lineManager: LineFallbackManager(),
      playerCreator: (engine) {
        final player = engine == PlayerEngine.mediaKit ? _SyncOutput() : _Player(selectedEngine: engine);
        created.add(player);
        return player;
      },
      audioModeServiceSync: (_, _) async {},
      audioSessionStart: (_) async {},
      useHardStopOnExit: () => true,
    )..configureDefaultEngine(PlayerEngine.fijk);
    final room = LiveRoom(roomId: 'a', platform: 'douyu', status: true);
    await manager.play('old', ['old'], {}, room: room, startMuted: true);
    expect(manager.currentEngine, PlayerEngine.fijk);
    expect(await manager.acquireCommentaryEngine(room: room, volume: .4), isTrue);
    expect(created.first.disposed, isTrue);
    expect(manager.currentEngine, PlayerEngine.mediaKit);
    expect(created.last.volume, .4);
    await manager.play('new', ['new'], {}, room: room, startMuted: true);
    expect(manager.currentEngine, PlayerEngine.mediaKit);
    expect(created, hasLength(2));
    await expectLater(manager.switchEngine(PlayerEngine.fijk), throwsStateError);
    manager.releaseCommentaryEngine();
    await manager.play('normal', ['normal'], {}, room: room, startMuted: true);
    expect(manager.currentEngine, PlayerEngine.fijk);
    expect(created, hasLength(3));
    await manager.dispose();
  });

  test('failed synchronization engine keeps A alive and audible', () async {
    final original = _Player(selectedEngine: PlayerEngine.fijk);
    final replacement = _SyncOutput()..failOpen = true;
    final manager = PlayerManager(
      fallbackManager: EngineFallbackManager(defaultEngine: PlayerEngine.fijk, supportedEngines: PlayerEngine.values),
      lineManager: LineFallbackManager(),
      playerCreator: (engine) => engine == PlayerEngine.mediaKit ? replacement : original,
      audioModeServiceSync: (_, _) async {},
      audioSessionStart: (_) async {},
      useHardStopOnExit: () => true,
    )..configureDefaultEngine(PlayerEngine.fijk);
    final room = LiveRoom(roomId: 'a', platform: 'douyu', status: true);
    await manager.play('old', ['old'], {}, room: room, startMuted: true);
    await expectLater(manager.acquireCommentaryEngine(room: room, volume: .6), throwsStateError);
    expect(manager.currentPlayer, same(original));
    expect(original.disposed, isFalse);
    expect(original.volume, .6);
    expect(replacement.disposed, isTrue);
    await manager.dispose();
  });

  test('exiting while the synchronization engine opens disposes only its unpublished replacement', () async {
    final original = _Player(selectedEngine: PlayerEngine.fijk);
    final replacement = _SyncOutput()..pendingOpen = Completer<void>();
    final manager = PlayerManager(
      fallbackManager: EngineFallbackManager(defaultEngine: PlayerEngine.fijk, supportedEngines: PlayerEngine.values),
      lineManager: LineFallbackManager(),
      playerCreator: (engine) => engine == PlayerEngine.mediaKit ? replacement : original,
      audioModeServiceSync: (_, _) async {},
      audioSessionStart: (_) async {},
      useHardStopOnExit: () => true,
    )..configureDefaultEngine(PlayerEngine.fijk);
    final room = LiveRoom(roomId: 'a', platform: 'douyu', status: true);
    await manager.play('old', ['old'], {}, room: room, startMuted: true);
    final acquiring = manager.acquireCommentaryEngine(room: room, volume: .3);
    await Future<void>.delayed(Duration.zero);
    manager.releaseCommentaryEngine();
    replacement.pendingOpen!.complete();
    expect(await acquiring, isFalse);
    expect(manager.currentPlayer, same(original));
    expect(original.disposed, isFalse);
    expect(original.volume, .3);
    expect(replacement.disposed, isTrue);
    await manager.dispose();
  });

  test('EOF and network error refresh once, preserve quality and notify sync without replacing the player', () async {
    final player = _Player();
    final refresher = _Refresher();
    final manager = _manager(player, refresher);
    final delegate = _ReloadDelegate();
    manager.controlDelegate = delegate;
    final refreshed = <RefreshedLiveSource>[];
    final subscription = manager.onLiveSourceRefreshed.listen(refreshed.add);
    final room = LiveRoom(roomId: 'a', platform: 'douyu', status: true);
    await manager.play(
      'old',
      ['old', 'backup'],
      {},
      room: room,
      startMuted: true,
      quality: LivePlayQuality(quality: '高清', id: 500),
      qualityIndex: 1,
    );
    await Future<void>.delayed(Duration.zero);
    player.playing.add(false);
    player.completed.add(true);
    player.errors.add(PlayerException(message: 'network', type: PlayerErrorType.network));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await Future<void>.delayed(Duration.zero);
    expect(refresher.calls, 1);
    expect(refresher.quality?.selectionId, 500);
    expect(player.opened, ['old', 'fresh']);
    expect(manager.currentPlayer, same(player));
    expect(delegate.reloading, 1);
    expect(delegate.ready, 1);
    expect(refreshed.single.url, 'fresh');
    expect(manager.hasError.value, isFalse);
    await subscription.cancel();
    await manager.dispose();
  });

  test('a queued recovery cannot reopen a room after switching A', () async {
    final player = _Player();
    final refresher = _Refresher()..pending = Completer<RefreshedLiveSource>();
    final manager = _manager(player, refresher);
    final room = LiveRoom(roomId: 'a', platform: 'douyu', status: true);
    await manager.play('old-a', ['old-a'], {}, room: room, startMuted: true);
    await Future<void>.delayed(Duration.zero);
    player.completed.add(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(refresher.calls, 1);
    final next = LiveRoom(roomId: 'b', platform: 'douyu', status: true);
    await manager.play('new-b', ['new-b'], {}, room: next, startMuted: true);
    refresher.pending!.complete(_source(room));
    await Future<void>.delayed(Duration.zero);
    expect(player.opened, ['old-a', 'new-b']);
    expect(manager.currentFloatRoom, next);
    await manager.dispose();
  });

  test('pause cancels pending refresh and a late native error cannot restart playback', () async {
    final player = _Player();
    final refresher = _Refresher()..pending = Completer<RefreshedLiveSource>();
    final manager = _manager(player, refresher);
    final room = LiveRoom(roomId: 'a', platform: 'douyu', status: true);
    await manager.play('old', ['old', 'backup'], {}, room: room, startMuted: true);
    await Future<void>.delayed(Duration.zero);
    player.completed.add(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await manager.pause();
    player.errors.add(PlayerException(message: 'late error', type: PlayerErrorType.source));
    refresher.pending!.complete(_source(room));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(player.opened, ['old']);
    expect(player.isPlayingNow, isFalse);
    await manager.dispose();
  });
}

PlayerManager _manager(_Player player, _Refresher refresher) => PlayerManager(
  fallbackManager: EngineFallbackManager(
    defaultEngine: PlayerEngine.mediaKit,
    supportedEngines: [PlayerEngine.mediaKit],
  ),
  lineManager: LineFallbackManager(),
  playerCreator: (_) => player,
  sourceRefresher: refresher,
  audioModeServiceSync: (_, _) async {},
  audioSessionStart: (_) async {},
  useHardStopOnExit: () => true,
)..configureDefaultEngine(PlayerEngine.mediaKit);

RefreshedLiveSource _source(LiveRoom room) => RefreshedLiveSource(
  room: room,
  qualities: [LivePlayQuality(quality: '高清', id: 500)],
  qualityIndex: 0,
  urls: ['fresh'],
  lineIndex: 0,
  headers: {},
);

class _Refresher extends LiveSourceRefresher {
  int calls = 0;
  LivePlayQuality? quality;
  Completer<RefreshedLiveSource>? pending;
  @override
  Future<RefreshedLiveSource> resolve({
    required LiveRoom room,
    required LivePlayQuality? preferredQuality,
    required int preferredQualityIndex,
    required int preferredLineIndex,
    required String previousUrl,
    bool advanceLine = false,
  }) {
    calls++;
    quality = preferredQuality;
    return pending?.future ?? Future.value(_source(room));
  }
}

class _ReloadDelegate implements LiveAudioControlDelegate, PrimaryPlaybackReloadDelegate {
  int reloading = 0;
  int ready = 0;
  @override
  void markPrimaryReloading() => reloading++;
  @override
  Future<void> onPrimaryReady() async {
    ready++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements UnifiedPlayer {
  _Player({this.selectedEngine = PlayerEngine.mediaKit});
  final PlayerEngine selectedEngine;
  bool failOpen = false;
  bool disposed = false;
  double volume = 1;
  Completer<void>? pendingOpen;
  final playing = BehaviorSubject.seeded(false);
  final completed = PublishSubject<bool>();
  final errors = PublishSubject<PlayerException>();
  final opened = <String>[];
  @override
  Future<void> init({bool audioOnly = false}) async {}
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
    if (failOpen) throw StateError('cannot open');
    await pendingOpen?.future;
    opened.add(url);
    playing.add(true);
  }

  @override
  Future<void> play() async {
    playing.add(true);
  }

  @override
  Future<void> pause() async {
    playing.add(false);
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> hardDispose() async {
    disposed = true;
    await playing.close();
    await completed.close();
    await errors.close();
  }

  @override
  PlayerEngine get engine => selectedEngine;
  @override
  bool get isPlayingNow => playing.value;
  @override
  Stream<bool> get onPlaying => playing.stream;
  @override
  Stream<bool> get onLoading => const Stream.empty();
  @override
  Stream<bool> get onComplete => completed.stream;
  @override
  Stream<PlayerException> get onError => errors.stream;
  @override
  Stream<PlayerState> get onStateChanged => const Stream.empty();
  @override
  Stream<int?> get width => const Stream.empty();
  @override
  Stream<int?> get height => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SyncOutput extends _Player implements SyncCapablePlayer {}
