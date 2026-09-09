import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/services/desktop_shutdown.dart';

void main() {
  test('native Quit and window close await one ordered cleanup', () async {
    final events = <String>[];
    final detached = Completer<void>();
    final released = Completer<void>();
    final shutdown = DesktopShutdown(
      detachViews: () async {
        events.add('detach');
        await detached.future;
      },
      closeResources: () async {
        events.add('close');
        await released.future;
      },
    );
    final first = shutdown.run();
    final second = shutdown.run();
    expect(identical(first, second), isTrue);
    expect(events, ['detach']);
    detached.complete();
    await Future<void>.delayed(Duration.zero);
    expect(events, ['detach', 'close']);
    var done = false;
    unawaited(first.then((_) => done = true));
    expect(done, isFalse);
    released.complete();
    await first;
    await second;
    await shutdown.run();
    expect(events, ['detach', 'close']);
  });

  test('failed cleanup is reported and can be retried, never forced through', () async {
    var attempts = 0;
    final shutdown = DesktopShutdown(
      detachViews: () async {},
      closeResources: () async {
        if (++attempts == 1) throw StateError('busy');
      },
    );
    await expectLater(shutdown.run(), throwsStateError);
    await shutdown.run();
    expect(attempts, 2);
  });
}
