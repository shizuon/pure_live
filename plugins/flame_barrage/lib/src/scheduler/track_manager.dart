import '../core/barrage_config.dart';
import '../model/barrage/barrage_entry.dart';
import '../model/barrage/barrage_track.dart';

class TrackManager {
  final List<BarrageTrack> _tracks = [];
  List<BarrageTrack> get tracks => _tracks;

  double _lastHeight = -1.0;
  int _lastMaxTracks = -1;

  void initialize(BarrageConfig config, double screenHeight) {
    if (screenHeight <= 0) return;

    final double safeTrackHeight = config.trackHeight < (config.fontSize + 10)
        ? (config.fontSize + 10)
        : config.trackHeight;

    final double usableHeight = screenHeight * config.area;
    int calculatedTracks = (usableHeight / safeTrackHeight).floor();

    if (calculatedTracks <= 0) calculatedTracks = 1;

    if (_lastHeight == screenHeight && _lastMaxTracks == calculatedTracks && _tracks.length == calculatedTracks) {
      return;
    }

    _lastHeight = screenHeight;
    _lastMaxTracks = calculatedTracks;

    final Map<int, BarrageTrack> oldTracksMap = {for (var t in _tracks) t.index: t};
    _tracks.clear();

    for (int i = 0; i < calculatedTracks; i++) {
      final oldTrack = oldTracksMap[i];
      if (oldTrack != null) {
        _tracks.add(oldTrack);
      } else {
        _tracks.add(BarrageTrack(index: i));
      }
    }
  }

  void forceRefresh(BarrageConfig config, double screenHeight) {
    _lastHeight = -1.0;
    _lastMaxTracks = -1;
    initialize(config, screenHeight);
  }

  void updateMetrics(Iterable<BarrageEntry> entries, {required double screenWidth, required int now}) {
    for (final track in _tracks) {
      track.activeCount = 0;
      track.avgSpeed = 0;
    }

    // Group entries in one pass. Track indices stay contiguous after resize;
    // entries from lanes that have disappeared are excluded until recycled.
    for (final entry in entries) {
      if (!entry.active || entry.track < 0 || entry.track >= _tracks.length) continue;
      final track = _tracks[entry.track];
      if (track.activeCount == 0 || entry.x > track.lastEntry!.x) {
        track.lastEntry = entry;
        track.lastRight = entry.x + entry.width;
      }
      track.activeCount++;
      track.avgSpeed += entry.speed;
    }

    for (final track in _tracks) {
      final count = track.activeCount;
      track.density = screenWidth > 0 ? (count * 150.0) / screenWidth : 0.0;
      if (count > 0) {
        track.avgSpeed /= count;
      } else if (!track.locked || now >= track.lockedUntil) {
        track.locked = false;
        track.lockedUntil = 0;
        track.lastRight = 0;
        track.lastEntry = null;
      }
    }
  }
}
