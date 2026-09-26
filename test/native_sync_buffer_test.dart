import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/utils/native_sync_buffer.dart';

void main() {
  const original = {
    'cache-secs': '600',
    'demuxer-readahead-secs': '2',
    'demuxer-max-bytes': '33554432',
    'cache-pause-wait': '1',
  };
  test('reserve and restore exact native options without touching timeline or decoder', () async {
    final values = Map<String, String>.from(original);
    final buffer = NativeSyncBuffer(
      read: (key) async => values[key]!,
      write: (key, value) async {
        expect(original.containsKey(key), isTrue);
        values[key] = value;
      },
      available: () => true,
    );
    await buffer.reserve(const Duration(seconds: 15));
    expect(values['cache-secs'], '23');
    expect(values['demuxer-readahead-secs'], '23');
    expect(values['demuxer-max-bytes'], '134217728');
    await buffer.reserve(const Duration(seconds: 5));
    expect(values['cache-secs'], '23');
    await buffer.restore();
    expect(values, original);
    await buffer.close();
  });
  test('partial native failure restores all successfully changed options', () async {
    final values = Map<String, String>.from(original);
    var fail = true;
    final buffer = NativeSyncBuffer(
      read: (key) async => values[key]!,
      write: (key, value) async {
        if (key == 'demuxer-readahead-secs' && fail) {
          fail = false;
          throw StateError('fixture');
        }
        values[key] = value;
      },
      available: () => true,
    );
    await expectLater(buffer.reserve(const Duration(seconds: 15)), throwsStateError);
    expect(values, original);
    await buffer.reserve(const Duration(seconds: 10));
    expect(values['cache-secs'], '18');
    await buffer.restore();
    expect(values, original);
  });
  test('exit queued during property read runs after reserve and restores original', () async {
    final values = Map<String, String>.from(original);
    final gate = Completer<void>();
    var first = true;
    final buffer = NativeSyncBuffer(
      read: (key) async {
        if (first) {
          first = false;
          await gate.future;
        }
        return values[key]!;
      },
      write: (key, value) async {
        values[key] = value;
      },
      available: () => true,
    );
    final reserve = buffer.reserve(const Duration(seconds: 15));
    final restore = buffer.restore();
    gate.complete();
    await Future.wait([reserve, restore]);
    expect(values, original);
  });
  test('disposal fences delayed reads and prevents writes to released native handle', () async {
    final gate = Completer<void>();
    var writes = 0;
    final started = Completer<void>();
    final buffer = NativeSyncBuffer(
      read: (key) async {
        if (!started.isCompleted) {
          started.complete();
          await gate.future;
        }
        return original[key]!;
      },
      write: (_, _) async {
        writes++;
      },
      available: () => true,
    );
    final reserve = buffer.reserve(const Duration(seconds: 15));
    await started.future;
    final closed = buffer.close();
    gate.complete();
    await Future.wait([reserve, closed]);
    expect(writes, 0);
    await buffer.reserve(const Duration(seconds: 10));
    expect(writes, 0);
  });
}
