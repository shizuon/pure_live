import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/core/audio_interruption_recovery.dart';

void main() {
  test('interruption never resumes a session that was already paused', () async {
    final output = _Output()..playing = false;
    await output.recovery.handle(PlaybackInterruption.pause, begin: true);
    await output.recovery.handle(PlaybackInterruption.pause, begin: false);
    expect(output.playCalls, 0);
    expect(output.playing, isFalse);
  });

  test('normal interruption resumes once, but newer user pause cancels resume', () async {
    final output = _Output();
    await output.recovery.handle(PlaybackInterruption.pause, begin: true);
    await output.recovery.handle(PlaybackInterruption.pause, begin: false);
    expect(output.playCalls, 1);
    await output.recovery.handle(PlaybackInterruption.pause, begin: true);
    await output.pause();
    await output.recovery.handle(PlaybackInterruption.pause, begin: false);
    expect(output.playCalls, 1);
    expect(output.playing, isFalse);
  });

  test('nested interruptions resume only after the final end', () async {
    final output = _Output();
    await output.recovery.handle(PlaybackInterruption.pause, begin: true);
    await output.recovery.handle(PlaybackInterruption.pause, begin: true);
    await output.recovery.handle(PlaybackInterruption.pause, begin: false);
    expect(output.playCalls, 0);
    await output.recovery.handle(PlaybackInterruption.pause, begin: false);
    expect(output.playCalls, 1);
  });

  test('duck restores the original non-max volume and respects volume changes', () async {
    final output = _Output()..volume = .4;
    await output.recovery.handle(PlaybackInterruption.duck, begin: true);
    expect(output.volume, closeTo(.08, .0001));
    await output.recovery.handle(PlaybackInterruption.duck, begin: false);
    expect(output.volume, .4);
    await output.recovery.handle(PlaybackInterruption.duck, begin: true);
    await output.setVolume(.3);
    await output.recovery.handle(PlaybackInterruption.duck, begin: false);
    expect(output.volume, .3);
  });

  test('a user pause while the native interruption pause is pending wins', () async {
    final output = _Output()..pendingPause = Completer<void>();
    final beginning = output.recovery.handle(PlaybackInterruption.pause, begin: true);
    await Future<void>.delayed(Duration.zero);
    output.transportRevision++;
    output.pendingPause!.complete();
    await beginning;
    await output.recovery.handle(PlaybackInterruption.pause, begin: false);
    expect(output.playCalls, 0);
  });

  test('stop resets interruption ownership so a late end cannot resume', () async {
    final output = _Output();
    await output.recovery.handle(PlaybackInterruption.pause, begin: true);
    output.recovery.reset();
    await output.recovery.handle(PlaybackInterruption.pause, begin: false);
    expect(output.playCalls, 0);
  });
}

class _Output {
  bool playing = true;
  double volume = 1;
  int transportRevision = 0;
  int volumeRevision = 0;
  int playCalls = 0;
  Completer<void>? pendingPause;
  late final recovery = AudioInterruptionRecovery(
    isPlaying: () => playing,
    volume: () => volume,
    transportRevision: () => transportRevision,
    volumeRevision: () => volumeRevision,
    pause: pause,
    play: play,
    setVolume: setVolume,
  );
  Future<void> pause() async {
    transportRevision++;
    playing = false;
    await pendingPause?.future;
  }

  Future<void> play() async {
    transportRevision++;
    playCalls++;
    playing = true;
  }

  Future<void> setVolume(double value) async {
    volumeRevision++;
    volume = value;
  }
}
