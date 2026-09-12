import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/utils/macos_decoder_status.dart';

class _Native {
  final observers = <String, Future<void> Function(String)>{};
  final properties = {'hwdec-current': 'no', 'video-format': 'h264', 'video-out-params/w': '1920', 'vid': '1'};
  Completer<String>? pendingDecoder;
  int reads = 0;

  Future<void> observeProperty(String key, Future<void> Function(String) callback) async => observers[key] = callback;
  Future<void> unobserveProperty(String key) async => observers.remove(key);
  Future<String> getProperty(String key) async {
    reads++;
    if (key == 'hwdec-current' && pendingDecoder != null) return pendingDecoder!.future;
    return properties[key]!;
  }

  void notify() {
    for (final callback in observers.values) {
      unawaited(callback(''));
    }
  }
}

void main() {
  test('strict mode stops initial software fallback once, then releases observers and timers', () {
    fakeAsync((async) {
      final native = _Native();
      var pauses = 0;
      var errors = 0;
      final guard = MacosHardwareDecodeGuard(native: native, pause: () async => pauses++, onRejected: () => errors++);
      unawaited(guard.attach());
      async.flushMicrotasks();
      expect(native.observers.length, 2);
      guard.activate(videoEnabled: true);
      native.notify();
      async.elapse(const Duration(milliseconds: 150));
      expect(pauses, 1);
      expect(errors, 1);
      expect(guard.rejected, isTrue);
      final reads = native.reads;
      native.notify();
      async.elapse(const Duration(seconds: 30));
      expect(native.reads, reads); // no permanent polling loop
      expect(pauses, 1);
      unawaited(guard.dispose());
      async.flushMicrotasks();
      expect(native.observers, isEmpty);
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test('startup and B audio-only are ignored; calibration re-enables strict checks', () {
    fakeAsync((async) {
      final native = _Native();
      var errors = 0;
      final guard = MacosHardwareDecodeGuard(native: native, pause: () async {}, onRejected: () => errors++);
      unawaited(guard.attach());
      async.flushMicrotasks();
      guard.activate(videoEnabled: false);
      native.notify();
      async.elapse(const Duration(seconds: 1));
      expect(native.reads, 0);
      native.properties['video-out-params/w'] = '';
      guard.activate(videoEnabled: true);
      async.elapse(const Duration(seconds: 1));
      expect(errors, 0);
      native.properties['video-out-params/w'] = '1920';
      native.properties['hwdec-current'] = 'videotoolbox';
      native.notify();
      async.elapse(const Duration(seconds: 1));
      expect(errors, 0);
      native.properties['hwdec-current'] = 'no';
      native.notify();
      async.elapse(const Duration(seconds: 1));
      expect(errors, 1);
      unawaited(guard.dispose());
      async.flushMicrotasks();
    });
  });

  test('stale checks cannot pause a replacement stream or disposed player', () {
    for (final dispose in [false, true]) {
      fakeAsync((async) {
        final native = _Native()..pendingDecoder = Completer<String>();
        var pauses = 0;
        final guard = MacosHardwareDecodeGuard(native: native, pause: () async => pauses++, onRejected: () {});
        unawaited(guard.attach());
        async.flushMicrotasks();
        guard.activate(videoEnabled: true);
        async.elapse(const Duration(milliseconds: 150));
        if (dispose) {
          unawaited(guard.dispose());
        } else {
          guard.suspend();
        }
        native.pendingDecoder!.complete('no');
        async.flushMicrotasks();
        expect(pauses, 0);
        unawaited(guard.dispose());
        async.flushMicrotasks();
      });
    }
  });

  test('new source can use hardware after a rejected source', () {
    fakeAsync((async) {
      final native = _Native();
      var errors = 0;
      final guard = MacosHardwareDecodeGuard(native: native, pause: () async {}, onRejected: () => errors++);
      unawaited(guard.attach());
      async.flushMicrotasks();
      guard.activate(videoEnabled: true);
      async.elapse(const Duration(seconds: 1));
      expect(errors, 1);
      guard.suspend();
      native.properties['hwdec-current'] = 'videotoolbox';
      guard.activate(videoEnabled: true);
      async.elapse(const Duration(seconds: 1));
      expect(guard.rejected, isFalse);
      expect(errors, 1);
      unawaited(guard.dispose());
      async.flushMicrotasks();
    });
  });
}
