import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/core/live_playback_recovery.dart';

void main() {
  test('initial open, recording and user pause cannot trigger automatic recovery', () {
    fakeAsync((clock) {
      var opens = 0;
      final recovery = LivePlaybackRecovery(
        reopen: (_) async {
          opens++;
          return LiveRecoveryResult.reopened;
        },
        onExhausted: (_) => fail('not a recovery session'),
      );
      recovery.startSession(enabled: true);
      expect(recovery.request(), isFalse);
      recovery.startSession(enabled: false);
      recovery.observe(playing: true);
      expect(recovery.request(), isFalse);
      recovery.startSession(enabled: true);
      recovery.observe(playing: true);
      recovery.request();
      recovery.setWanted(false);
      expect(recovery.request(), isFalse);
      clock.elapse(const Duration(minutes: 1));
      expect(opens, 0);
      recovery.cancel();
    });
  });

  test('error and EOF before the retry starts share one request', () {
    fakeAsync((clock) {
      var opens = 0;
      final recovery = LivePlaybackRecovery(
        reopen: (_) async {
          opens++;
          return LiveRecoveryResult.reopened;
        },
        onExhausted: (_) => fail('unexpected failure'),
      )..startSession(enabled: true);
      recovery.observe(playing: true);
      recovery.request();
      recovery.request();
      clock.elapse(const Duration(seconds: 1));
      expect(opens, 1);
      expect(recovery.isRecovering, isFalse);
      recovery.cancel();
    });
  });

  test('native failure during reopen consumes one attempt and retries fresh URLs', () {
    fakeAsync((clock) {
      var opens = 0;
      late LivePlaybackRecovery recovery;
      recovery = LivePlaybackRecovery(
        reopen: (_) async {
          opens++;
          if (opens == 1) recovery.request();
          return LiveRecoveryResult.reopened;
        },
        onExhausted: (_) => fail('unexpected failure'),
      )..startSession(enabled: true);
      recovery.observe(playing: true);
      recovery.request();
      clock.elapse(const Duration(seconds: 1));
      expect(opens, 1);
      clock.elapse(const Duration(seconds: 3));
      expect(opens, 2);
      recovery.cancel();
    });
  });

  test('three retries at 1, 3 and 8 seconds exhaust without an infinite loop', () {
    fakeAsync((clock) {
      var opens = 0;
      final failures = <bool>[];
      final recovery = LivePlaybackRecovery(
        reopen: (_) async {
          opens++;
          return LiveRecoveryResult.retry;
        },
        onExhausted: failures.add,
      )..startSession(enabled: true);
      recovery.observe(playing: true);
      recovery.request();
      clock.elapse(const Duration(seconds: 11));
      expect(opens, 2);
      clock.elapse(const Duration(seconds: 1));
      expect(opens, 3);
      expect(failures, [false]);
      recovery.request();
      clock.elapse(const Duration(minutes: 2));
      expect(opens, 3);
      expect(failures, [false]);
      recovery.cancel();
    });
  });

  test('short playing signals do not reset retries; 30 stable seconds do', () {
    fakeAsync((clock) {
      var opens = 0;
      final failures = <bool>[];
      final recovery = LivePlaybackRecovery(
        reopen: (_) async {
          opens++;
          return LiveRecoveryResult.reopened;
        },
        onExhausted: failures.add,
      )..startSession(enabled: true);
      recovery.observe(playing: true);
      recovery.request();
      clock.elapse(const Duration(seconds: 1));
      clock.elapse(const Duration(seconds: 29));
      recovery.observe(buffering: true);
      recovery.observe(buffering: false);
      recovery.request();
      clock.elapse(const Duration(seconds: 1));
      expect(opens, 1, reason: 'second retry must retain its 3s delay');
      clock.elapse(const Duration(seconds: 2));
      expect(opens, 2);
      clock.elapse(const Duration(seconds: 30));
      recovery.request();
      clock.elapse(const Duration(seconds: 1));
      expect(opens, 3, reason: 'stable playback resets the next delay to 1s');
      expect(failures, isEmpty);
      recovery.cancel();
    });
  });

  test('leaving while resolving invalidates results; old completion cannot affect a new session', () {
    fakeAsync((clock) {
      final pending = Completer<LiveRecoveryResult>();
      bool Function()? oldCurrent;
      var opens = 0;
      final recovery = LivePlaybackRecovery(
        reopen: (isCurrent) {
          opens++;
          if (opens == 1) {
            oldCurrent = isCurrent;
            return pending.future;
          }
          return Future.value(LiveRecoveryResult.reopened);
        },
        onExhausted: (_) => fail('old recovery must not report errors'),
      )..startSession(enabled: true);
      recovery.observe(playing: true);
      recovery.request();
      clock.elapse(const Duration(seconds: 1));
      recovery.startSession(enabled: true);
      expect(oldCurrent!(), isFalse);
      recovery.observe(playing: true);
      recovery.request();
      pending.complete(LiveRecoveryResult.retry);
      clock.elapse(const Duration(seconds: 1));
      expect(opens, 2);
      expect(recovery.isRecovering, isFalse);
      recovery.cancel();
    });
  });

  test('confirmed offline stops the recovery ladder immediately', () {
    fakeAsync((clock) {
      var opens = 0;
      final failures = <bool>[];
      final recovery = LivePlaybackRecovery(
        reopen: (_) async {
          opens++;
          return LiveRecoveryResult.offline;
        },
        onExhausted: failures.add,
      )..startSession(enabled: true);
      recovery.observe(playing: true);
      recovery.request();
      clock.elapse(const Duration(minutes: 1));
      expect(opens, 1);
      expect(failures, [true]);
      recovery.cancel();
    });
  });
}
