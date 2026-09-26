import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/model/live_play_quality.dart';

import 'playback_header_resolver.dart';

class LiveSourceOffline implements Exception {
  const LiveSourceOffline();
}

class RefreshedLiveSource {
  const RefreshedLiveSource({
    required this.room,
    required this.qualities,
    required this.qualityIndex,
    required this.urls,
    required this.lineIndex,
    required this.headers,
  });

  final LiveRoom room;
  final List<LivePlayQuality> qualities;
  final int qualityIndex;
  final List<String> urls;
  final int lineIndex;
  final Map<String, String> headers;
  LivePlayQuality get quality => qualities[qualityIndex];
  String get url => urls[lineIndex];
}

/// Refreshes signed live URLs without rebuilding the room or its danmaku.
/// It contains no GetX state writes, and callers fence the result before use.
class LiveSourceRefresher {
  LiveSourceRefresher({LiveSite Function(String)? siteFor, Future<Map<String, String>> Function(LiveRoom)? headersFor})
    : _siteFor = siteFor ?? ((platform) => Sites.of(platform).liveSite),
      _headersFor =
          headersFor ?? ((room) => PlaybackHeaderResolver.resolve(platform: room.platform!, roomId: room.roomId!));

  final LiveSite Function(String) _siteFor;
  final Future<Map<String, String>> Function(LiveRoom) _headersFor;

  Future<RefreshedLiveSource> resolve({
    required LiveRoom room,
    required LivePlayQuality? preferredQuality,
    required int preferredQualityIndex,
    required int preferredLineIndex,
    required String previousUrl,
    bool advanceLine = false,
  }) async {
    final site = _siteFor(room.platform!);
    final fetched = await site.getRoomDetail(roomId: room.roomId!, platform: room.platform!);
    if (fetched.liveStatus == LiveStatus.offline ||
        fetched.liveStatus == LiveStatus.banned ||
        fetched.liveStatus == LiveStatus.replay ||
        fetched.isRecord == true) {
      throw const LiveSourceOffline();
    }
    if (fetched.status != true && fetched.liveStatus != LiveStatus.live) {
      throw StateError('Live status is not available');
    }
    final detail = fetched.withAudienceFallbackFrom(room).fillFromDetail(room);
    var qualities = await site.getPlayQualites(detail: detail);
    if (qualities.isEmpty) throw StateError('No live qualities available');
    var qualityIndex = preferredQuality == null
        ? -1
        : qualities.indexWhere((q) => q.selectionId.toString() == preferredQuality.selectionId.toString());
    if (qualityIndex < 0 && preferredQuality != null) {
      qualityIndex = qualities.indexWhere((q) => q.quality == preferredQuality.quality);
    }
    if (qualityIndex < 0) qualityIndex = preferredQualityIndex.clamp(0, qualities.length - 1);
    final resolved = await site.resolvePlayUrls(detail: detail, quality: qualities[qualityIndex]);
    qualities = resolved.withAcknowledgedQuality(qualities);
    final urls = normalizeResolvedPlayUrls(resolved.urls);
    if (urls.isEmpty) throw StateError('No fresh live URL available');
    if (resolved.appliedQualityData != null) {
      final applied = qualities.indexWhere((q) => q.selectionId.toString() == resolved.appliedQualityData.toString());
      if (applied >= 0) qualityIndex = applied;
    }
    var lineIndex = preferredLineIndex.clamp(0, urls.length - 1);
    final previousHost = Uri.tryParse(previousUrl)?.host;
    if (previousHost != null && previousHost.isNotEmpty && Uri.tryParse(urls[lineIndex])?.host != previousHost) {
      final sameHost = urls.indexWhere((url) => Uri.tryParse(url)?.host == previousHost);
      if (sameHost >= 0) lineIndex = sameHost;
    }
    if (advanceLine && urls.length > 1) lineIndex = (lineIndex + 1) % urls.length;
    // Signing may update platform header state; resolve headers afterwards.
    final headers = await _headersFor(detail);
    return RefreshedLiveSource(
      room: detail,
      qualities: List.unmodifiable(qualities),
      qualityIndex: qualityIndex,
      urls: urls,
      lineIndex: lineIndex,
      headers: Map.unmodifiable(headers),
    );
  }
}
