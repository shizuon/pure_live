import 'dart:developer';

import 'core/player_manager.dart';
import 'models/player_engine.dart';
import 'core/line_fallback_manager.dart';
import 'core/engine_fallback_manager.dart';
import 'core/player_pool.dart';
import 'adapters/player_adapter_factory.dart';

import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/modules/live_play/controllers/commentary_sync_controller.dart';
import 'package:pure_live/player/core/live_audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:pure_live/modules/live_play/widgets/commentary_video_overlay.dart';
import 'core/mobile_commentary_observer.dart';

class GlobalPlayerService {
  GlobalPlayerService._();

  static final GlobalPlayerService instance = GlobalPlayerService._();

  late final PlayerManager playerManager;
  late final PlayerPool playerPool;
  late final CommentarySyncController commentarySyncController;
  PlayerManager get player => playerManager;
  bool _initialized = false;
  MobileCommentaryObserver? _mobileCommentaryObserver;
  Future<void>? _initializationFuture;
  Future<void>? _disposeFuture;

  bool get initialized => _initialized;

  Future<void> initialize({PlayerEngine defaultEngine = PlayerEngine.mediaKit}) async {
    if (_initialized) return;
    final inFlight = _initializationFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final operation = _initialize(defaultEngine);
    _initializationFuture = operation;
    try {
      await operation;
    } finally {
      if (identical(_initializationFuture, operation)) _initializationFuture = null;
    }
  }

  Future<void> _initialize(PlayerEngine defaultEngine) async {
    playerPool = PlayerPool(factory: PlayerAdapterFactory.create);

    // 1. Instantiate the Orchestrator with all its specialized managers
    playerManager = PlayerManager(
      fallbackManager: EngineFallbackManager(
        defaultEngine: defaultEngine,
        supportedEngines: PlatformUtils.isMobile ? PlayerEngine.values : [PlayerEngine.mediaKit],
      ),
      lineManager: LineFallbackManager(),
    );

    // 2. Keep native decoders, network workers and textures cold until the
    // first room is opened. This avoids paying hundreds of MiB and background
    // CPU merely for browsing the home/settings UI.
    await playerManager.initialize(engine: defaultEngine, audioOnly: false);
    commentarySyncController = CommentarySyncController(primaryManager: playerManager, playerPool: playerPool);
    playerManager.controlDelegate = commentarySyncController;
    playerManager.compactCommentaryBuilder = () => Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            CommentaryVideoOverlay(
              sync: commentarySyncController,
              controlsVisible: false,
              controlsLocked: true,
              compact: true,
              onInteraction: () {},
            ),
          ],
        ),
      ),
    );
    await LiveAudioService.setControlDelegate(commentarySyncController);
    if (PlatformUtils.isMobile) {
      _mobileCommentaryObserver = MobileCommentaryObserver(commentarySyncController);
    }
    _initialized = true;
    log("GlobalPlayerService: Player initialized.", name: "GlobalPlayerService");
  }

  /// Global dispose - Call this only when the app is being destroyed
  Future<void> dispose() async {
    final initialization = _initializationFuture;
    if (initialization != null) await initialization;
    await (_disposeFuture ??= _dispose());
  }

  Future<void> _dispose() async {
    if (!_initialized) return;
    await _mobileCommentaryObserver?.dispose();
    _mobileCommentaryObserver = null;
    await commentarySyncController.dispose();
    playerManager.controlDelegate = null;
    playerManager.compactCommentaryBuilder = null;
    await LiveAudioService.setControlDelegate(null);
    await playerManager.dispose();
    await playerPool.disposeAll();
    _initialized = false;
    log("GlobalPlayerService: Disposed.", name: "GlobalPlayerService");
  }
}
