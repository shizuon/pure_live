import 'dart:async';

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
  final CommentaryCandidates candidates;
}

/// A demand-driven cursor: requesting a line never prefetches another quality.
/// Cancellation cannot abort a platform HTTP request already in flight, but
/// drops its result and prevents both further requests and player creation.
class CommentaryCandidates {
  CommentaryCandidates.fromList(List<ResolvedStreamCandidate> candidates)
    : _ready = List.of(candidates),
      _qualities = const [],
      _loadQuality = null;

  CommentaryCandidates._(this._qualities, this._loadQuality);

  List<ResolvedStreamCandidate> _ready = [];
  final List<LivePlayQuality> _qualities;
  final Future<List<ResolvedStreamCandidate>> Function(LivePlayQuality)? _loadQuality;
  final Set<String> _seenUrls = {};
  int _qualityIndex = 0;
  int _lineIndex = 0;
  bool _cancelled = false;
  Future<ResolvedStreamCandidate?>? _inFlight;

  Future<ResolvedStreamCandidate?> next() {
    if (_cancelled) return Future.value();
    return _inFlight ??= _next().whenComplete(() => _inFlight = null);
  }

  Future<ResolvedStreamCandidate?> _next() async {
    while (!_cancelled) {
      while (_lineIndex < _ready.length) {
        final candidate = _ready[_lineIndex++];
        if (_seenUrls.add(candidate.url)) return candidate;
      }
      if (_qualityIndex >= _qualities.length) return null;
      final quality = _qualities[_qualityIndex++];
      try {
        final candidates = await _loadQuality!(quality);
        if (_cancelled) return null;
        _ready = candidates;
        _lineIndex = 0;
      } catch (_) {
        // A failed or expired quality does not block the remaining qualities.
      }
    }
    return null;
  }

  void cancel() {
    _cancelled = true;
    _ready = [];
    _seenUrls.clear();
  }
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
        candidates: CommentaryCandidates.fromList([
          ResolvedStreamCandidate(
            room: detail,
            quality: quality,
            url: detail.link!,
            playUrls: [detail.link!],
            headers: headers,
          ),
        ]),
      );
    }

    final qualities = await site.liveSite.getPlayQualites(detail: detail);
    final candidates = buildCandidates(
      room: detail,
      qualities: qualities,
      headers: headers,
      getPlayUrls: (quality) => site.liveSite.getPlayUrls(detail: detail, quality: quality),
    );

    return ResolvedCommentarySource(room: detail, candidates: candidates);
  }

  static CommentaryCandidates buildCandidates({
    required LiveRoom room,
    required List<LivePlayQuality> qualities,
    required Map<String, String> headers,
    required Future<List<String>> Function(LivePlayQuality quality) getPlayUrls,
  }) => CommentaryCandidates._(lowestQualityFirst(qualities), (quality) async {
    final urls = await getPlayUrls(quality);
    final validUrls = List<String>.unmodifiable(urls.where((url) => url.isNotEmpty).toSet());
    return [
      for (final url in validUrls)
        ResolvedStreamCandidate(room: room, quality: quality, url: url, playUrls: validUrls, headers: headers),
    ];
  });

  static List<LivePlayQuality> lowestQualityFirst(List<LivePlayQuality> qualities) {
    return qualities.reversed.toList(growable: false);
  }

  static Future<Map<String, String>> headersFor(LiveRoom room) async {
    final platform = room.platform;
    if (platform == null || platform.isEmpty) return const {};
    return PlaybackHeaderResolver.resolve(platform: platform, roomId: room.roomId ?? '');
  }
}
