import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/core/mobile_commentary_lifecycle.dart';

void main() {
  test('background permission keeps audio; PiP restores video without reopening', () async {
    final session = _Session();
    await session.update(visible: false, allowed: true);
    expect(session.events, ['video:false']);
    expect(session.playing, isTrue);
    await session.update(visible: false, pip: true, allowed: true);
    expect(session.events, ['video:false', 'video:true']);
    await session.lifecycle.dispose();
  });
  test('disabled background pauses both; foreground resumes only that pause', () async {
    final session = _Session();
    await session.update(visible: false);
    expect(session.events, ['pause', 'video:false']);
    await session.update(visible: false);
    expect(session.events, hasLength(2));
    await session.update(visible: true);
    expect(session.events, ['pause', 'video:false', 'video:true', 'play']);
    await session.lifecycle.dispose();
  });
  test('new user pause and room change revoke automatic resume', () async {
    final session = _Session();
    await session.update(visible: false);
    session.revision++;
    await session.update(visible: true);
    expect(session.events, isNot(contains('play')));
    session.playing = true;
    await session.update(visible: false);
    session.id++;
    session.events.clear();
    await session.update(visible: true);
    expect(session.events, isEmpty);
    await session.lifecycle.dispose();
  });
  test('return during video suspension waits then restores final visibility', () async {
    final session = _Session();
    final entered = Completer<void>();
    final blocked = Completer<void>();
    session.onVideo = (visible) async {
      if (!visible) {
        entered.complete();
        await blocked.future;
      }
    };
    final hide = session.update(visible: false, allowed: true);
    await entered.future;
    final show = session.update(visible: true);
    blocked.complete();
    await Future.wait([hide, show]);
    expect(session.events, ['video:false', 'video:true']);
    await session.lifecycle.dispose();
  });
  test('dispose and inactive sessions never resurrect playback', () async {
    final session = _Session();
    await session.update(visible: false);
    session.engaged = false;
    await session.update(visible: true);
    await session.lifecycle.dispose();
    session.engaged = true;
    await session.update(visible: true);
    expect(session.events, ['pause', 'video:false']);
  });
}

class _Session {
  bool engaged = true;
  bool playing = true;
  int revision = 0;
  int id = 1;
  final events = <String>[];
  Future<void> Function(bool)? onVideo;
  late final lifecycle = MobileCommentaryLifecycle(
    engaged: () => engaged,
    sessionId: () => id,
    isPlaying: () => playing,
    transportRevision: () => revision,
    pause: () async {
      revision++;
      playing = false;
      events.add('pause');
    },
    play: () async {
      revision++;
      playing = true;
      events.add('play');
    },
    setVideoVisible: (visible) async {
      events.add('video:$visible');
      await onVideo?.call(visible);
    },
  );
  Future<void> update({required bool visible, bool pip = false, bool allowed = false}) =>
      lifecycle.update(visible: visible, inPip: pip, allowBackground: allowed);
}
