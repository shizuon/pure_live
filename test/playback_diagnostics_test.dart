import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/utils/playback_diagnostics.dart';

void main() {
  test('snapshot preserves cumulative counters and unavailable fields separately', () async {
    final d = await PlaybackDiagnostics.read(
      (key) async => switch (key) {
        'time-pos' => '10.25',
        'audio-pts' => '10.125',
        'avsync' => '-0.125',
        'demuxer-cache-duration' => '0',
        'paused-for-cache' => 'yes',
        'pause' => 'no',
        'speed' => '1.02',
        'decoder-frame-drop-count' => '2',
        'frame-drop-count' => '30',
        _ => throw StateError('unsupported'),
      },
    );
    expect(d.number('time-pos'), '10.25');
    expect(d.number('audio-pts', digits: 3), '10.125');
    expect(d.number('avsync', digits: 3), '-0.125');
    expect(d.number('demuxer-cache-duration'), '0.00');
    expect(d.values['paused-for-cache'], 'yes');
    expect(d.number('frame-drop-count', digits: 0), '30');
    expect(d.values['eof-reached'], isNull);
  });
  test('signed audio timestamps and A/V differences retain their native direction', () async {
    final d = await PlaybackDiagnostics.read((key) async => key == 'avsync' ? '0.375' : '-0.250');
    expect(d.number('audio-pts', digits: 3), '-0.250');
    expect(d.number('avsync', digits: 3), '0.375');
    expect(d.number('demuxer-cache-duration'), '—');
  });
  test('malformed, negative and nonfinite native values are not shown as measurements', () async {
    for (final value in ['NaN', 'Infinity', '-1', '', 'unavailable']) {
      final d = await PlaybackDiagnostics.read((_) async => value);
      expect(d.number('demuxer-cache-duration'), '—');
      expect(d.values['paused-for-cache'], isNull);
    }
  });
  test('hung property cannot leave refresh busy forever; supported values survive', () {
    fakeAsync((clock) {
      PlaybackDiagnostics? d;
      unawaited(
        PlaybackDiagnostics.read((key) => key == 'time-pos' ? Future.value('12') : Completer<String>().future)
            .then((value) => d = value),
      );
      clock.flushMicrotasks();
      expect(d, isNull);
      clock.elapse(const Duration(seconds: 2));
      expect(d!.number('time-pos'), '12.00');
      expect(d!.number('frame-drop-count'), '—');
    });
  });
}
