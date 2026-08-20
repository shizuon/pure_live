import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/service/commentary_danmaku_delay_queue.dart';

void main() {
  group('commentary danmaku delay queue', () {
    test('positive offset delays messages by the selected stream offset', () {
      fakeAsync((async) {
        final emitted = <int>[];
        final start = DateTime(2026);
        final queue = CommentaryDanmakuDelayQueue<int>(onEmit: emitted.add, now: () => start.add(async.elapsed));

        queue.updateOffset(500);
        queue.add(1);
        async.elapse(const Duration(milliseconds: 499));
        expect(emitted, isEmpty);

        async.elapse(const Duration(milliseconds: 1));
        expect(emitted, [1]);
        queue.dispose();
      });
    });

    test('negative and zero offsets emit immediately', () {
      final emitted = <int>[];
      final queue = CommentaryDanmakuDelayQueue<int>(onEmit: emitted.add);

      queue.updateOffset(-500);
      queue.add(1);
      queue.updateOffset(0);
      queue.add(2);

      expect(emitted, [1, 2]);
      expect(queue.delayMs, 0);
      queue.dispose();
    });

    test('offset changes reschedule messages that are still pending', () {
      fakeAsync((async) {
        final emitted = <int>[];
        final start = DateTime(2026);
        final queue = CommentaryDanmakuDelayQueue<int>(onEmit: emitted.add, now: () => start.add(async.elapsed));

        queue.updateOffset(1000);
        queue.add(1);
        async.elapse(const Duration(milliseconds: 400));
        queue.updateOffset(500);
        async.elapse(const Duration(milliseconds: 99));
        expect(emitted, isEmpty);

        async.elapse(const Duration(milliseconds: 1));
        expect(emitted, [1]);

        queue.updateOffset(500);
        queue.add(2);
        async.elapse(const Duration(milliseconds: 200));
        queue.updateOffset(1000);
        async.elapse(const Duration(milliseconds: 799));
        expect(emitted, [1]);

        async.elapse(const Duration(milliseconds: 1));
        expect(emitted, [1, 2]);
        queue.dispose();
      });
    });

    test('clear cancels pending messages', () {
      fakeAsync((async) {
        final emitted = <int>[];
        final start = DateTime(2026);
        final queue = CommentaryDanmakuDelayQueue<int>(onEmit: emitted.add, now: () => start.add(async.elapsed));

        queue.updateOffset(1000);
        queue.add(1);
        queue.clear();
        async.elapse(const Duration(seconds: 2));

        expect(emitted, isEmpty);
        expect(queue.pendingCount, 0);
        queue.dispose();
      });
    });

    test('pending queue stays bounded and preserves remaining order', () {
      fakeAsync((async) {
        final emitted = <int>[];
        final start = DateTime(2026);
        final queue = CommentaryDanmakuDelayQueue<int>(
          onEmit: emitted.add,
          now: () => start.add(async.elapsed),
          maxPendingMessages: 2,
        );

        queue.updateOffset(100);
        queue.add(1);
        queue.add(2);
        queue.add(3);
        expect(queue.pendingCount, 2);

        async.elapse(const Duration(milliseconds: 100));
        expect(emitted, [2, 3]);
        queue.dispose();
      });
    });
  });
}
