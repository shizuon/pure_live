import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/live_play/controllers/commentary_sync_controller.dart';
import 'package:pure_live/modules/live_play/states/commentary_sync_state.dart';

import 'live_audio_service.dart';
import 'mobile_commentary_lifecycle.dart';

/// One application-level owner survives live-page/PiP presentation changes.
class MobileCommentaryObserver with WidgetsBindingObserver {
  MobileCommentaryObserver(this.sync) {
    _lifecycle = MobileCommentaryLifecycle(
      engaged: () => sync.isEngaged,
      sessionId: () => sync.mobileSessionId,
      isPlaying: () => sync.sessionPlaying,
      transportRevision: () => sync.transportRevision,
      pause: sync.pause,
      play: sync.play,
      setVideoVisible: sync.setMobileVideoVisible,
    );
    final initial = WidgetsBinding.instance.lifecycleState;
    _state = initial == AppLifecycleState.inactive ? AppLifecycleState.resumed : initial ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _pip = ever(sync.primaryManager.isInPip, (_) => _update());
    _session = ever<CommentarySyncState>(sync.state, (_) => _update());
    _update();
  }

  final CommentarySyncController sync;
  late final MobileCommentaryLifecycle _lifecycle;
  late final Worker _pip;
  late final Worker _session;
  late AppLifecycleState _state;
  (bool, bool, bool, int, bool)? _last;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive includes Control Center, system prompts and split-screen focus
    // changes; those do not mean the visible video should be torn down.
    if (state == AppLifecycleState.inactive) return;
    _state = state;
    _update();
  }

  void _update() {
    final visible = _state == AppLifecycleState.resumed;
    final pip = sync.primaryManager.isInPip.value;
    final allowed = LiveAudioService.shouldContinueInBackground;
    final next = (visible, pip, allowed, sync.mobileSessionId, sync.isActive);
    if (_last == next) return;
    _last = next;
    // Activation must acquire both players before resource transitions. The
    // active-state transition triggers another update after a reconnect.
    if (!sync.isActive) return;
    unawaited(
      _lifecycle.update(visible: visible, inPip: pip, allowBackground: allowed).catchError((Object error) {
        debugPrint('Commentary background transition failed: $error');
      }),
    );
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _pip.dispose();
    _session.dispose();
    await _lifecycle.dispose();
  }
}
