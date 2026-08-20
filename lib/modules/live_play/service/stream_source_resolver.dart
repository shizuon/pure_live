import 'package:pure_live/common/index.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/player/core/playback_header_resolver.dart';

class ResolvedStreamCandidate {
  const ResolvedStreamCandidate({
    required this.room,
    required this.quality,
    required this.url,
    required this.playUrls,
    required this.headers,
  });

  final LiveRoom room;
  final LivePlayQuality quality;
  final String url;
  final List<String> playUrls;
  final Map<String, String> headers;
}

class ResolvedCommentarySource {
  const ResolvedCommentarySource({required this.room, required this.candidates});

  final LiveRoom room;
  final List<ResolvedStreamCandidate> candidates;
}

class StreamSourceResolver {
  const StreamSourceResolver();

  Future<ResolvedCommentarySource> resolveCommentary(LiveRoom selectedRoom) async {
    final platform = selectedRoom.platform;
    final roomId = selectedRoom.roomId;
    if (platform == null || platform.isEmpty || roomId == null || roomId.isEmpty) {
      throw StateError('Invalid commentary room');
    }

    final site = Sites.of(platform);
    final detail = await site.liveSite.getRoomDetail(roomId: roomId, platform: platform);
    final isLive = detail.status == true || detail.isRecord == true || detail.liveStatus == LiveStatus.live;
    if (!isLive) throw StateError('Commentary room is offline');

    final headers = await headersFor(detail);
    if (platform == Sites.iptvSite && (detail.link?.isNotEmpty ?? false)) {
      final quality = LivePlayQuality(quality: '原画');
      return ResolvedCommentarySource(
        room: detail,
        candidates: [
          ResolvedStreamCandidate(
            room: detail,
            quality: quality,
            url: detail.link!,
            playUrls: [detail.link!],
            headers: headers,
          ),
        ],
      );
    }

    final qualities = await site.liveSite.getPlayQualites(detail: detail);
    final candidates = await buildCandidates(
      room: detail,
      qualities: qualities,
      headers: headers,
      getPlayUrls: (quality) => site.liveSite.getPlayUrls(detail: detail, quality: quality),
    );

    if (candidates.isEmpty) throw StateError('No commentary stream available');
    return ResolvedCommentarySource(room: detail, candidates: candidates);
  }

  static Future<List<ResolvedStreamCandidate>> buildCandidates({
    required LiveRoom room,
    required List<LivePlayQuality> qualities,
    required Map<String, String> headers,
    required Future<List<String>> Function(LivePlayQuality quality) getPlayUrls,
  }) async {
    final candidates = <ResolvedStreamCandidate>[];
    final seenUrls = <String>{};
    for (final quality in lowestQualityFirst(qualities)) {
      List<String> urls;
      try {
        urls = await getPlayUrls(quality);
      } catch (_) {
        // A single failed quality must not prevent the resolver from trying
        // the remaining qualities and their CDN lines.
        continue;
      }
      final validUrls = urls.where((url) => url.isNotEmpty).toSet().toList(growable: false);
      for (final url in validUrls) {
        if (!seenUrls.add(url)) continue;
        candidates.add(
          ResolvedStreamCandidate(
            room: room,
            quality: quality,
            url: url,
            playUrls: List.unmodifiable(validUrls),
            headers: headers,
          ),
        );
      }
    }
    return candidates;
  }

  static List<LivePlayQuality> lowestQualityFirst(List<LivePlayQuality> qualities) {
    return qualities.reversed.toList(growable: false);
  }

  static Future<Map<String, String>> headersFor(LiveRoom room) async {
    final platform = room.platform;
    if (platform == null || platform.isEmpty) return const {};
    return PlaybackHeaderResolver.resolve(platform: platform, roomId: room.roomId ?? '');
  }
}
