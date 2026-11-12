import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = BarrageConfig(fontSize: 20, trackHeight: 36, area: 1);

  test('twelve lanes inspect 48 visible entries once and retain their metrics', () {
    final manager = TrackManager()..initialize(config, 432);
    final entries = List.generate(48, (index) {
      return _entry(track: index % 12, x: index.toDouble(), speed: 60 + index.toDouble());
    });
    var visits = 0;
    manager.updateMetrics(
      entries.map((entry) {
        visits++;
        return entry;
      }),
      screenWidth: 1200,
      now: 0,
    );

    expect(manager.tracks, hasLength(12));
    expect(visits, 48);
    for (var index = 0; index < 12; index++) {
      final track = manager.tracks[index];
      expect(track.activeCount, 4);
      expect(track.avgSpeed, 78 + index);
      expect(track.density, .5);
      expect(track.lastEntry, same(entries[index + 36]));
      expect(track.lastRight, 136 + index);
    }
  });

  test('metric refresh skips inactive and removed lanes and keeps first equal x', () {
    final manager = TrackManager()..initialize(config, 72);
    final first = _entry(track: 0, x: 200, speed: 40);
    final tied = _entry(track: 0, x: 200, speed: 60)..width = 300;
    final inactive = _entry(track: 0, x: 400, speed: 500)..active = false;
    final removed = _entry(track: 1, x: 500, speed: 500);
    manager.initialize(config, 36);
    manager.updateMetrics([first, tied, inactive, removed], screenWidth: 1000, now: 0);

    final track = manager.tracks.single;
    expect(track.activeCount, 2);
    expect(track.avgSpeed, 50);
    expect(track.density, .3);
    expect(track.lastEntry, same(first));
    expect(track.lastRight, 300);

    manager.updateMetrics([], screenWidth: 0, now: 1);
    expect(track.activeCount, 0);
    expect(track.avgSpeed, 0);
    expect(track.density, 0);
    expect(track.lastEntry, isNull);
    expect(track.lastRight, 0);
  });

  test('empty fixed lane keeps its reservation until the original deadline', () {
    final manager = TrackManager()..initialize(config, 36);
    final track = manager.tracks.single;
    final fixed = _entry(track: 0, x: 100, speed: 0);
    track
      ..locked = true
      ..lockedUntil = 1000;
    manager.updateMetrics([fixed], screenWidth: 1000, now: 0);
    manager.updateMetrics([], screenWidth: 1000, now: 999);
    expect(track.locked, isTrue);
    expect(track.lastEntry, same(fixed));
    expect(track.lastRight, 200);
    expect(track.activeCount, 0);

    manager.updateMetrics([], screenWidth: 1000, now: 1000);
    expect(track.locked, isFalse);
    expect(track.lockedUntil, 0);
    expect(track.lastEntry, isNull);
    expect(track.lastRight, 0);
  });
}

BarrageEntry _entry({required int track, required double x, required double speed}) {
  return BarrageEntry(item: const BarrageItem(content: 'metric sample'), creationTime: 0)
    ..track = track
    ..x = x
    ..width = 100
    ..speed = speed;
}
