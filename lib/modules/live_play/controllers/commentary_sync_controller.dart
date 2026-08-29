import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/service/stream_source_resolver.dart';
import 'package:pure_live/modules/live_play/service/commentary_sync_math.dart';
import 'package:pure_live/modules/live_play/service/commentary_platform_support.dart';
import 'package:pure_live/modules/live_play/states/commentary_sync_state.dart';
import 'package:pure_live/player/core/live_audio_control_delegate.dart';
import 'package:pure_live/player/core/player_manager.dart';
import 'package:pure_live/player/core/player_pool.dart';
import 'package:pure_live/player/interface/sync_capable_player.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/player/models/player_slot.dart';

class CommentarySyncController implements LiveAudioControlDelegate, PrimaryPlaybackReloadDelegate {
  CommentarySyncController({
    required this.primaryManager,
    required this.playerPool,
    StreamSourceResolver? resolver,
    bool Function()? platformSupportProbe,
  }) : resolver = resolver ?? const StreamSourceResolver(),
       _platformSupportProbe = platformSupportProbe ?? _defaultPlatformSupportProbe {
    _primaryLoadingSubscription = primaryManager.onLoading.distinct().listen(_handlePrimaryLoading);
  }

  static bool _defaultPlatformSupportProbe() => CommentaryPlatformSupport.isSupported;

  static const int minOffsetMs = -30000;
  static const int maxOffsetMs = 30000;
  static const Duration _playingTimeout = Duration(seconds: 15);
  static const Duration _stablePlaybackWindow = Duration(seconds: 2);
  static const Duration _bufferReconnectThreshold = Duration(seconds: 3);
  static const List<Duration> _retryDelays = [Duration(seconds: 1), Duration(seconds: 3), Duration(seconds: 8)];

  final PlayerManager primaryManager;
  final PlayerPool playerPool;
  final StreamSourceResolver resolver;
  final bool Function() _platformSupportProbe;

  final Rx<CommentarySyncState> state = const CommentarySyncState().obs;

  UnifiedPlayer? _companion;
  SyncCapablePlayer? _companionSync;
  SyncCapablePlayer? _primarySync;
  ResolvedCommentarySource? _source;
  int _candidateIndex = 0;
  int _generation = 0;
  int _consecutiveDriftSamples = 0;
  int _appliedOffsetMs = 0;
  int _requestedOffsetMs = 0;
  double _baselineGapMs = 0;
  double _primaryRestoreVolume = 1;
  double _companionRate = 1;
  bool _manualStop = false;
  bool _transportPausedByUser = false;
  bool _stoppingPrimary = false;
  bool _primaryReloading = false;
  bool _primaryWasBuffering = false;
  bool _bufferFallbackActive = false;
  bool _handlingCompanionFailure = false;
  bool _commentaryAudioSelected = false;
  bool _previewTrackChanging = false;
  int _audioTransitionEpoch = 0;
  Timer? _driftTimer;
  Timer? _bufferReconnectTimer;
  Future<void>? _offsetWork;
  Future<void> _audioTransitionTail = Future<void>.value();
  Completer<void>? _offsetDelayCancellation;
  final List<StreamSubscription<dynamic>> _companionSubscriptions = [];
  late final StreamSubscription<bool> _primaryLoadingSubscription;

  bool get isSupported => _platformSupportProbe();
  bool get isEngaged => state.value.isEngaged;
  bool get isActive => state.value.isActive;
  bool get isPlaying => primaryManager.isPlayingNow;
  double get outputVolume => state.value.outputVolume;
  UnifiedPlayer? get companionPreviewPlayer => _companion;

  Future<void> activate({required LiveRoom videoRoom, required LiveRoom audioRoom, double? primaryVolume}) async {
    if (!isSupported) {
      throw UnsupportedError('Commentary sync is unavailable on this platform');
    }
    if (videoRoom == audioRoom) {
      throw StateError('Video and commentary rooms must be different');
    }
    if (primaryManager.currentPlayer is! SyncCapablePlayer) {
      throw StateError('The current player does not support synchronization');
    }

    await exit();
    final generation = ++_generation;
    _manualStop = false;
    final volume = (primaryVolume ?? videoRoom.getSavedVolume()).clamp(0.0, 1.0).toDouble();
    _primaryRestoreVolume = volume;
    _requestedOffsetMs = 0;
    _transportPausedByUser = false;
    state.value = CommentarySyncState(
      status: CommentarySyncStatus.loading,
      videoRoom: videoRoom,
      audioRoom: audioRoom,
      outputVolume: volume,
      previewVisible: true,
      message: '正在连接解说源',
    );

    try {
      _source = await resolver.resolveCommentary(audioRoom);
      if (generation != _generation) return;
      state.value = state.value.copyWith(audioRoom: _source!.room);
      _candidateIndex = 0;
      await _openAvailableCandidate(generation: generation);
      if (generation != _generation) return;
      await _finishAvailableCandidate(generation: generation, targetOffsetMs: 0);
    } catch (error) {
      if (generation != _generation) return;
      await _restorePrimaryAudio();
      state.value = state.value.copyWith(status: CommentarySyncStatus.error, message: error.toString());
    }
  }

  Future<void> _openAvailableCandidate({required int generation}) async {
    final candidates = _source?.candidates ?? const <ResolvedStreamCandidate>[];
    Object? lastError;
    while (_candidateIndex < candidates.length && generation == _generation) {
      try {
        await _createCompanion();
        final candidate = candidates[_candidateIndex];
        await _companion!.setVolume(0);
        await _companion!.setDataSource(
          candidate.url,
          candidate.playUrls,
          candidate.headers,
          room: candidate.room,
          audioOnly: false,
          startMuted: true,
        );
        await _companion!.onPlaying.where((playing) => playing).first.timeout(_playingTimeout);
        if (!await _waitForAudioTrack()) {
          throw StateError('No audio track in commentary stream');
        }
        return;
      } catch (error) {
        lastError = error;
        _candidateIndex++;
        await _disposeCompanion();
      }
    }
    throw lastError ?? StateError('No commentary stream available');
  }

  Future<void> _createCompanion() async {
    await _disposeCompanion();
    _companion = await playerPool.getPlayer(
      PlayerEngine.mediaKit,
      slot: PlayerSlot.commentaryAudio,
      // B uses its lowest-quality video track for the calibration preview.
      // It is still a separate player and only its audio is sent to output.
      audioOnly: false,
    );
    _companionSync = _companion as SyncCapablePlayer;
    _bindCompanionEvents(_companion!);
  }

  Future<bool> _waitForAudioTrack() async {
    final sync = _companionSync;
    if (sync == null) return false;
    for (var i = 0; i < 50; i++) {
      if (sync.hasAudioTrack) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return sync.hasAudioTrack;
  }

  void _bindCompanionEvents(UnifiedPlayer player) {
    _companionSubscriptions.add(
      player.onError.listen((_) {
        if (isActive && !_manualStop) unawaited(_handleCompanionFailure());
      }),
    );
    _companionSubscriptions.add(
      player.onComplete.where((complete) => complete).listen((_) {
        if (isActive && !_manualStop) unawaited(_handleCompanionFailure());
      }),
    );
    _companionSubscriptions.add(
      player.onLoading.distinct().listen((loading) {
        if (_manualStop || _previewTrackChanging) return;
        if (loading && isActive) {
          unawaited(_handleCompanionBuffering());
        } else if (!loading && _bufferFallbackActive) {
          unawaited(_recoverFromCompanionBuffering());
        }
      }),
    );
  }

  Future<void> _finishActivation({
    required int generation,
    required int targetOffsetMs,
    Duration stableFor = _stablePlaybackWindow,
  }) async {
    if (generation != _generation) return;
    _primarySync = primaryManager.currentPlayer as SyncCapablePlayer?;
    if (_primarySync == null || _companionSync == null) {
      throw StateError('Synchronization player unavailable');
    }

    await _waitUntilStable(generation: generation, stableFor: stableFor);
    if (generation != _generation || _manualStop) return;
    await _setCompanionRate(1);
    _captureBaseline();
    _appliedOffsetMs = 0;
    _requestedOffsetMs = targetOffsetMs;
    final switched = await _crossfadeToCommentary(generation);
    if (!switched || generation != _generation || _manualStop) return;
    state.value = state.value.copyWith(status: CommentarySyncStatus.active, offsetMs: 0, message: '粗同步完成，可按需要微调');
    if (targetOffsetMs != 0) await setOffset(targetOffsetMs);
    _startDriftMonitor();
  }

  Future<void> _finishAvailableCandidate({required int generation, required int targetOffsetMs}) async {
    Object? lastError;
    while (generation == _generation && !_manualStop) {
      try {
        await _finishActivation(generation: generation, targetOffsetMs: targetOffsetMs);
        return;
      } catch (error) {
        lastError = error;
        await _restorePrimaryAudio();
        _candidateIndex++;
        await _disposeCompanion();
        await _openAvailableCandidate(generation: generation);
      }
    }
    throw lastError ?? StateError('Commentary activation cancelled');
  }

  Future<void> _waitUntilStable({required int generation, required Duration stableFor}) async {
    final deadline = DateTime.now().add(_playingTimeout);
    DateTime? stableSince;
    while (DateTime.now().isBefore(deadline)) {
      if (generation != _generation || _manualStop) {
        throw StateError('Commentary activation cancelled');
      }
      final companion = _companion;
      final primary = _primarySync;
      final stable =
          companion != null &&
          primary != null &&
          companion.isPlayingNow &&
          primaryManager.isPlayingNow &&
          !primary.isBufferingNow &&
          !(_companionSync?.isBufferingNow ?? true);
      if (stable) {
        stableSince ??= DateTime.now();
        if (DateTime.now().difference(stableSince) >= stableFor) return;
      } else {
        stableSince = null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('Streams did not become stable', _playingTimeout);
  }

  void _captureBaseline() {
    final videoMs = _primarySync?.currentPosition.inMicroseconds ?? 0;
    final audioMs = _companionSync?.currentPosition.inMicroseconds ?? 0;
    _baselineGapMs = (audioMs - videoMs) / 1000;
    _consecutiveDriftSamples = 0;
  }

  Future<void> adjustOffset(int deltaMs) => setOffset(_requestedOffsetMs + deltaMs);

  Future<void> setOffset(int requestedOffsetMs) async {
    if (!isActive || _primarySync == null || _companionSync == null) return;
    final target = CommentarySyncMath.clampOffset(requestedOffsetMs, minimum: minOffsetMs, maximum: maxOffsetMs);
    _requestedOffsetMs = target;
    state.value = state.value.copyWith(status: CommentarySyncStatus.calibrating, offsetMs: target);
    final running = _offsetWork;
    if (running != null) return running;
    final work = _drainOffsetRequests();
    _offsetWork = work;
    return work;
  }

  Future<void> _drainOffsetRequests() async {
    final generation = _generation;
    try {
      while (generation == _generation && isActive) {
        final target = _requestedOffsetMs;
        final delta = target - _appliedOffsetMs;
        if (delta == 0) break;
        await _setCompanionRate(1);
        final player = delta > 0 ? _companion : primaryManager.currentPlayer;
        if (player == null || _transportPausedByUser) break;
        final applied = await _pauseFor(player, Duration(milliseconds: delta.abs()), generation: generation);
        if (!applied) break;
        _appliedOffsetMs = target;
      }
    } finally {
      _offsetWork = null;
      if (generation == _generation && isActive) {
        final pending = _requestedOffsetMs != _appliedOffsetMs;
        state.value = state.value.copyWith(
          status: CommentarySyncStatus.active,
          offsetMs: _requestedOffsetMs,
          message: pending ? '偏移将在继续播放后应用' : null,
          clearMessage: !pending,
        );
        if (pending && !_transportPausedByUser && primaryManager.isPlayingNow && (_companion?.isPlayingNow ?? false)) {
          unawaited(setOffset(_requestedOffsetMs));
        }
      }
    }
  }

  Future<bool> _pauseFor(UnifiedPlayer player, Duration duration, {required int generation}) async {
    if (!player.isPlayingNow || _transportPausedByUser) return false;
    await player.pause();
    var completedNormally = false;
    final cancellation = Completer<void>();
    _offsetDelayCancellation = cancellation;
    try {
      await Future.any([
        Future<void>.delayed(duration).then((_) {
          completedNormally = true;
        }),
        cancellation.future,
      ]);
    } finally {
      if (identical(_offsetDelayCancellation, cancellation)) {
        _offsetDelayCancellation = null;
      }
      if (!_transportPausedByUser && !_stoppingPrimary) {
        await player.play();
      }
    }
    return completedNormally && generation == _generation && isEngaged;
  }

  Future<void> resetOffset() => setOffset(0);

  Future<void> showCalibrationPreview() async {
    if (!isEngaged) return;
    state.value = state.value.copyWith(previewVisible: true, message: '请对照 A、B 画面中的时间戳进行校准');
    await _setCompanionVideoEnabled(true);
  }

  Future<void> finishCalibrationPreview() async {
    if (!isEngaged) return;
    state.value = state.value.copyWith(previewVisible: false, message: '校准画面已隐藏，可随时再次校准');
    await _setCompanionVideoEnabled(false);
  }

  Future<void> _setCompanionVideoEnabled(bool enabled) async {
    final companion = _companion;
    if (companion == null || _previewTrackChanging) return;
    _previewTrackChanging = true;
    try {
      await companion.setAudioOnly(!enabled).timeout(const Duration(seconds: 5));
    } catch (_) {
      // B audio remains authoritative after calibration. A failed optional
      // video-track toggle must not interrupt it or trigger source failover.
    } finally {
      _previewTrackChanging = false;
    }
  }

  Future<void> resync({Future<void> Function()? reopenPrimary}) async {
    final audioRoom = state.value.audioRoom;
    if (!isEngaged || audioRoom == null) return;
    final generation = ++_generation;
    final targetOffset = _requestedOffsetMs;
    _driftTimer?.cancel();
    _cancelBufferRecovery();
    _cancelOffsetDelay();
    state.value = state.value.copyWith(status: CommentarySyncStatus.loading, previewVisible: true, message: '正在重新同步');
    await _restorePrimaryAudio();
    await _disposeCompanion();

    try {
      final primaryFuture = reopenPrimary?.call() ?? primaryManager.replay(startMuted: false);
      final sourceFuture = resolver.resolveCommentary(audioRoom);
      _source = await sourceFuture;
      if (generation != _generation) return;
      state.value = state.value.copyWith(audioRoom: _source!.room);
      _candidateIndex = 0;
      await Future.wait([primaryFuture, _openAvailableCandidate(generation: generation)]);
      await primaryManager.onPlaying.where((playing) => playing).first.timeout(_playingTimeout);
      await _finishAvailableCandidate(generation: generation, targetOffsetMs: targetOffset);
    } catch (error) {
      if (generation != _generation) return;
      await _restorePrimaryAudio();
      state.value = state.value.copyWith(status: CommentarySyncStatus.error, message: error.toString());
    }
  }

  @override
  void markPrimaryReloading() {
    if (!isEngaged) return;
    _primaryReloading = true;
    _driftTimer?.cancel();
    _cancelOffsetDelay();
    unawaited(_setCompanionRate(1));
  }

  @override
  Future<void> onPrimaryReady() async {
    if (!isActive || _companionSync == null) return;
    final generation = _generation;
    _primaryReloading = false;
    _primarySync = primaryManager.currentPlayer as SyncCapablePlayer?;
    if (_primarySync == null) return;
    try {
      await _waitUntilStable(generation: generation, stableFor: const Duration(milliseconds: 500));
    } catch (_) {
      return;
    }
    await primaryManager.setVolume(0);
    primaryManager.setMutedForFutureReloads(true);
    _captureBaseline();
    final target = _requestedOffsetMs;
    _appliedOffsetMs = 0;
    if (target != 0) await setOffset(target);
    _startDriftMonitor();
  }

  void _handlePrimaryLoading(bool loading) {
    if (!isActive || _primaryReloading) return;
    if (loading) {
      _primaryWasBuffering = true;
      _consecutiveDriftSamples = 0;
      unawaited(_setCompanionRate(1));
      return;
    }
    if (_primaryWasBuffering) {
      _primaryWasBuffering = false;
      unawaited(_rebaselineAfterPrimaryBuffer());
    }
  }

  Future<void> _rebaselineAfterPrimaryBuffer() async {
    final generation = _generation;
    try {
      await _waitUntilStable(generation: generation, stableFor: const Duration(milliseconds: 500));
    } catch (_) {
      return;
    }
    if (generation != _generation || !isActive || _primaryReloading) return;
    final video = _primarySync;
    final audio = _companionSync;
    if (video == null || audio == null) return;
    final actualGapMs = (audio.currentPosition - video.currentPosition).inMicroseconds / 1000;
    // The already-applied user offset is part of the current gap. Adding it
    // back yields the new zero-offset baseline without applying the offset a
    // second time after a short primary-player buffer.
    _baselineGapMs = actualGapMs + _appliedOffsetMs;
    _consecutiveDriftSamples = 0;
    _startDriftMonitor();
  }

  void _startDriftMonitor() {
    _driftTimer?.cancel();
    _driftTimer = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_correctDrift()));
  }

  Future<void> _correctDrift() async {
    final video = _primarySync;
    final audio = _companionSync;
    if (!isActive || _primaryReloading || _offsetWork != null || video == null || audio == null) {
      return;
    }
    if (video.isBufferingNow || audio.isBufferingNow || !_companion!.isPlayingNow || !primaryManager.isPlayingNow) {
      _consecutiveDriftSamples = 0;
      await _setCompanionRate(1);
      return;
    }

    final actualGapMs = (audio.currentPosition - video.currentPosition).inMicroseconds / 1000;
    final desiredGapMs = CommentarySyncMath.desiredGapMs(baselineGapMs: _baselineGapMs, offsetMs: state.value.offsetMs);
    final errorMs = actualGapMs - desiredGapMs;
    if (errorMs.abs() <= 50) {
      _consecutiveDriftSamples = 0;
      await _setCompanionRate(1);
      return;
    }
    if (errorMs.abs() <= 150) {
      _consecutiveDriftSamples = 0;
      return;
    }

    _consecutiveDriftSamples++;
    if (_consecutiveDriftSamples < 3) return;
    final correctionRate = CommentarySyncMath.correctionRate(
      errorMs: errorMs,
      consecutiveSamples: _consecutiveDriftSamples,
    );
    _consecutiveDriftSamples = 0;
    await _setCompanionRate(correctionRate);
  }

  Future<void> _setCompanionRate(double rate) async {
    final audio = _companionSync;
    if (audio == null || (_companionRate - rate).abs() < 0.0001) return;
    await audio.setPlaybackRate(rate);
    _companionRate = rate;
  }

  Future<void> _handleCompanionBuffering() async {
    if (_manualStop || !isActive || _bufferFallbackActive) return;
    final generation = _generation;
    _bufferFallbackActive = true;
    _driftTimer?.cancel();
    _cancelOffsetDelay();
    await _setCompanionRate(1);
    await _restorePrimaryAudio();
    if (generation != _generation || _manualStop) return;
    state.value = state.value.copyWith(status: CommentarySyncStatus.reconnecting, message: '解说源缓冲中，已临时恢复原直播声音');
    _bufferReconnectTimer?.cancel();
    _bufferReconnectTimer = Timer(_bufferReconnectThreshold, () {
      if (generation == _generation && _bufferFallbackActive) {
        _bufferFallbackActive = false;
        unawaited(_handleCompanionFailure(allowReconnecting: true));
      }
    });
  }

  Future<void> _recoverFromCompanionBuffering() async {
    if (!_bufferFallbackActive || _manualStop) return;
    final generation = _generation;
    _bufferReconnectTimer?.cancel();
    _bufferReconnectTimer = null;
    try {
      await _finishActivation(generation: generation, targetOffsetMs: _requestedOffsetMs);
      if (generation == _generation) {
        _bufferFallbackActive = false;
        state.value = state.value.copyWith(message: '解说源已恢复，请确认同步');
      }
    } catch (_) {
      if (generation == _generation && !_manualStop) {
        _bufferFallbackActive = false;
        await _handleCompanionFailure(allowReconnecting: true);
      }
    }
  }

  Future<void> _handleCompanionFailure({bool allowReconnecting = false}) async {
    if (_manualStop || !isEngaged || _handlingCompanionFailure) return;
    if (!allowReconnecting && state.value.status == CommentarySyncStatus.reconnecting) {
      return;
    }
    _handlingCompanionFailure = true;
    try {
      final generation = ++_generation;
      _driftTimer?.cancel();
      _cancelBufferRecovery();
      _cancelOffsetDelay();
      await _setCompanionRate(1);
      await _restorePrimaryAudio();
      state.value = state.value.copyWith(status: CommentarySyncStatus.reconnecting, message: '解说源断开，正在重连');

      for (var attempt = 0; attempt < _retryDelays.length; attempt++) {
        await Future<void>.delayed(_retryDelays[attempt]);
        if (generation != _generation || _manualStop) return;
        try {
          final audioRoom = state.value.audioRoom;
          if (audioRoom == null) break;
          // Always obtain fresh signed URLs. Reusing the failed candidate list
          // makes recovery impossible when a CDN URL has expired.
          _source = await resolver.resolveCommentary(audioRoom);
          if (generation != _generation) return;
          state.value = state.value.copyWith(audioRoom: _source!.room);
          _candidateIndex = 0;
          await _openAvailableCandidate(generation: generation);
          await _finishAvailableCandidate(generation: generation, targetOffsetMs: _requestedOffsetMs);
          if (generation != _generation || _manualStop) return;
          if (!state.value.previewVisible) {
            await _setCompanionVideoEnabled(false);
          }
          state.value = state.value.copyWith(message: '解说源已恢复，请确认同步');
          return;
        } catch (_) {
          await _disposeCompanion();
          await _restorePrimaryAudio();
        }
      }

      if (generation == _generation) {
        state.value = state.value.copyWith(status: CommentarySyncStatus.error, message: '解说源重连失败，已恢复原直播声音');
      }
    } finally {
      _handlingCompanionFailure = false;
    }
  }

  Future<bool> _crossfadeToCommentary(int generation) async {
    final epoch = ++_audioTransitionEpoch;
    var completed = false;
    await _serializeAudioTransition(() async {
      final companion = _companion;
      if (companion == null || epoch != _audioTransitionEpoch) return;
      final commentaryVolume = state.value.outputVolume;
      for (var step = 1; step <= 5; step++) {
        if (generation != _generation || _manualStop || epoch != _audioTransitionEpoch) {
          return;
        }
        final ratio = step / 5;
        await Future.wait([
          primaryManager.setVolume(_primaryRestoreVolume * (1 - ratio)),
          companion.setVolume(commentaryVolume * ratio),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      if (generation != _generation || _manualStop || epoch != _audioTransitionEpoch) {
        return;
      }
      _commentaryAudioSelected = true;
      primaryManager.setMutedForFutureReloads(true);
      completed = true;
    });
    return completed;
  }

  Future<void> _restorePrimaryAudio() async {
    final epoch = ++_audioTransitionEpoch;
    await _serializeAudioTransition(() async {
      if (epoch != _audioTransitionEpoch) return;
      final companion = _companion;
      if (_commentaryAudioSelected && companion != null) {
        final commentaryVolume = state.value.outputVolume;
        for (var step = 1; step <= 5; step++) {
          if (epoch != _audioTransitionEpoch) return;
          final ratio = step / 5;
          await Future.wait([
            primaryManager.setVolume(_primaryRestoreVolume * ratio),
            companion.setVolume(commentaryVolume * (1 - ratio)),
          ]);
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
      if (epoch != _audioTransitionEpoch) return;
      try {
        await companion?.setVolume(0);
      } catch (_) {}
      await primaryManager.setVolume(_primaryRestoreVolume);
      primaryManager.setMutedForFutureReloads(false);
      _commentaryAudioSelected = false;
    });
  }

  Future<void> _serializeAudioTransition(Future<void> Function() transition) {
    final next = _audioTransitionTail.then((_) => transition(), onError: (_) => transition());
    _audioTransitionTail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<void> setOutputVolume(double volume) async {
    final safeVolume = volume.clamp(0.0, 1.0).toDouble();
    state.value = state.value.copyWith(outputVolume: safeVolume);
    if (isActive && _companion != null) {
      await _companion!.setVolume(safeVolume);
      await primaryManager.setVolume(0);
    } else if (!isEngaged) {
      _primaryRestoreVolume = safeVolume;
      await primaryManager.setVolume(safeVolume);
    } else {
      await primaryManager.setVolume(_primaryRestoreVolume);
    }
  }

  @override
  Future<void> setVolume(double volume) => setOutputVolume(volume);

  @override
  Future<void> play() async {
    _transportPausedByUser = false;
    if (isEngaged && _companion != null) {
      await Future.wait([primaryManager.resume(), _companion!.play()]);
    } else {
      await primaryManager.resume();
    }
    if (isActive && _requestedOffsetMs != _appliedOffsetMs) {
      await setOffset(_requestedOffsetMs);
    }
  }

  @override
  Future<void> pause() async {
    _transportPausedByUser = true;
    _cancelOffsetDelay();
    await _setCompanionRate(1);
    if (isEngaged && _companion != null) {
      await Future.wait([primaryManager.pause(), _companion!.pause()]);
    } else {
      await primaryManager.pause();
    }
  }

  Future<void> togglePlayPause() => isPlaying ? pause() : play();

  @override
  Future<void> stop() async {
    _stoppingPrimary = true;
    try {
      await exit(restorePrimary: false);
      await primaryManager.stop();
    } finally {
      _stoppingPrimary = false;
    }
  }

  Future<void> exit({bool restorePrimary = true}) async {
    _manualStop = true;
    _generation++;
    _driftTimer?.cancel();
    _driftTimer = null;
    _cancelBufferRecovery();
    _cancelOffsetDelay();
    if (restorePrimary && state.value.isEngaged) await _restorePrimaryAudio();
    await _disposeCompanion();
    _source = null;
    _primarySync = null;
    _candidateIndex = 0;
    _appliedOffsetMs = 0;
    _requestedOffsetMs = 0;
    _baselineGapMs = 0;
    _companionRate = 1;
    _transportPausedByUser = false;
    _primaryReloading = false;
    _primaryWasBuffering = false;
    _handlingCompanionFailure = false;
    _commentaryAudioSelected = false;
    _previewTrackChanging = false;
    state.value = const CommentarySyncState();
  }

  void _cancelBufferRecovery() {
    _bufferReconnectTimer?.cancel();
    _bufferReconnectTimer = null;
    _bufferFallbackActive = false;
  }

  void _cancelOffsetDelay() {
    final cancellation = _offsetDelayCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _offsetDelayCancellation = null;
  }

  Future<void> _disposeCompanion() async {
    _cancelBufferRecovery();
    for (final subscription in _companionSubscriptions) {
      await subscription.cancel();
    }
    _companionSubscriptions.clear();
    try {
      await _companionSync?.setPlaybackRate(1);
    } catch (_) {}
    await playerPool.removeFromCache(PlayerEngine.mediaKit, slot: PlayerSlot.commentaryAudio);
    _companion = null;
    _companionSync = null;
    _companionRate = 1;
  }

  Future<void> dispose() async {
    await exit();
    await _primaryLoadingSubscription.cancel();
    state.close();
  }
}
