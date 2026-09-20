import 'package:pure_live/model/live_play_quality.dart';

/// Pick a readable face/timestamp stream before calibration, so opening the
/// crop editor never needs a quality switch or a fresh live timeline.
abstract final class CommentaryQualityPolicy {
  static List<LivePlayQuality> order(List<LivePlayQuality> qualities, {String? preferredId}) {
    if (qualities.isEmpty) return const [];
    final preferred = preferredId == null ? -1 : qualities.indexWhere((q) => q.selectionId.toString() == preferredId);
    var selected = preferred;
    if (selected < 0) {
      // Platform rate IDs are opaque. Only an explicit M/Mbps label carries
      // bitrate semantics (Douyu's `rate=4`, for example, is not 4 Mbps).
      final bitrates = <(int, double)>[];
      for (var i = 0; i < qualities.length; i++) {
        final match = RegExp(r'(\d+(?:\.\d+)?)\s*[mM](?:bps)?', caseSensitive: false).firstMatch(qualities[i].quality);
        final rate = match == null ? null : double.tryParse(match.group(1)!);
        if (rate != null && rate >= 4) bitrates.add((i, rate));
      }
      bitrates.sort((a, b) => a.$2.compareTo(b.$2));
      if (bitrates.isNotEmpty) selected = bitrates.first.$1;
    }
    if (selected < 0) {
      selected = qualities.indexWhere(
        (q) => RegExp(r'1080|蓝光|藍光|超清|原画|原畫|source|original', caseSensitive: false).hasMatch(q.quality),
      );
    }
    // Upstream lists are ordered highest first; unknown naming should not
    // silently degrade a face overlay to the last/lowest rung.
    if (selected < 0) selected = 0;
    return [qualities[selected], ...qualities.take(selected).toList().reversed, ...qualities.skip(selected + 1)];
  }
}
