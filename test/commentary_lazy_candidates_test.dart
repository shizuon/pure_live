import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/service/stream_source_resolver.dart';

void main() {
  final room = LiveRoom(roomId: 'b', platform: 'test');
  List<LivePlayQuality> qualities() => ['high', 'mid', 'low'].map((q) => LivePlayQuality(quality: q)).toList();

  test('lowest quality starts before higher tiers are queried and exhausts same-quality lines first', () async {
    final calls = <String>[];
    final candidates = StreamSourceResolver.buildCandidates(
      room: room,
      qualities: qualities(),
      headers: const {'Referer': 'room-b'},
      getPlayUrls: (quality) async {
        calls.add(quality.quality);
        return switch (quality.quality) {
          'low' => ['low-1', '', 'low-1', 'low-2'],
          'mid' => ['low-2', 'mid-1'],
          _ => ['high-1'],
        };
      },
    );
    expect(calls, isEmpty);
    final first = await candidates.next();
    expect(first?.url, 'low-1');
    expect(first?.playUrls, ['low-1', 'low-2']);
    expect(first?.headers, {'Referer': 'room-b'});
    expect(calls, ['low']);
    expect((await candidates.next())?.url, 'low-2');
    expect(calls, ['low']);
    expect((await candidates.next())?.url, 'mid-1');
    expect(calls, ['low', 'mid']);
    expect((await candidates.next())?.url, 'high-1');
    expect(await candidates.next(), isNull);
    expect(calls, ['low', 'mid', 'high']);
  });

  test('cancellation drops an in-flight result and never requests another quality', () async {
    final pending = Completer<List<String>>();
    var calls = 0;
    final candidates = StreamSourceResolver.buildCandidates(
      room: room,
      qualities: qualities(),
      headers: const {},
      getPlayUrls: (_) {
        calls++;
        return pending.future;
      },
    );
    final first = candidates.next();
    expect(candidates.next(), same(first), reason: 'concurrent requests share one resolver call');
    candidates.cancel();
    pending.completeError(StateError('old room request failed'));
    expect(await first, isNull);
    expect(await candidates.next(), isNull);
    expect(calls, 1);
  });

  test('failed and empty qualities keep fallback available', () async {
    final candidates = StreamSourceResolver.buildCandidates(
      room: room,
      qualities: qualities(),
      headers: const {},
      getPlayUrls: (q) async {
        if (q.quality == 'low') throw StateError('expired URL');
        return q.quality == 'mid' ? [] : ['working'];
      },
    );
    expect((await candidates.next())?.url, 'working');
    expect(await candidates.next(), isNull);
  });
}
