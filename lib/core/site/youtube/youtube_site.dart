import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/danmaku/youtube_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/twitch/twitch_site.dart';
import 'package:pure_live/core/site/youtube/youtube_page.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/model/live_play_quality.dart';

class YouTubeSite extends LiveSite implements LiveSiteRoomRefresher, LiveSiteRecordRoomResolver {
  YouTubeSite() {
    id = 'youtube';
    name = 'YouTube';
  }
  static const headers = {'User-Agent': TwitchSite.defaultUa, 'Accept-Language': 'en-US,en;q=0.9'};
  static const androidClient = {
    'clientName': 'ANDROID',
    'clientVersion': '21.03.38',
    'androidSdkVersion': 30,
    'userAgent': 'com.google.android.youtube/21.03.38 (Linux; U; Android 11) gzip',
  };
  final _searches = <String, _YouTubeSearch>{};

  Future<String> page(String path, {Map<String, dynamic>? query}) =>
      HttpClient.instance.getText('https://www.youtube.com$path', header: headers, queryParameters: query);

  Future<dynamic> api(String operation, Map<String, dynamic> body) => HttpClient.instance.postJson(
    'https://www.youtube.com/youtubei/v1/$operation',
    data: body,
    header: operation == 'player' ? {'User-Agent': androidClient['userAgent']} : headers,
    queryParameters: {'prettyPrint': 'false'},
  );

  @override
  LiveDanmaku getDanmaku() => YouTubeDanmaku();

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async => [
    LiveCategory(
      id: 'live',
      name: 'YouTube Live',
      children: [
        for (final entry in {
          'live': '直播',
          'gaming': '游戏',
          'Counter-Strike': 'Counter-Strike',
          'music': '音乐',
          'news': '新闻',
          'sports': '体育',
        }.entries)
          LiveArea(
            platform: id,
            areaId: entry.key,
            shortName: entry.key,
            areaName: entry.value,
            areaType: 'live',
            typeName: 'YouTube Live',
          ),
      ],
    ),
  ];

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) =>
      searchRooms(category.shortName ?? 'live', page: page, pageSize: pageSize);

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) =>
      searchRooms('live', page: page, pageSize: pageSize);

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    final target = roomIdentity(keyword);
    final explicitRoom =
        keyword.contains('://') || keyword.trim().startsWith('@') || keyword.trim().startsWith('channel/');
    if (target != null && explicitRoom) return page == 1 ? [await getRoomDetail(roomId: target, platform: id)] : [];
    _YouTubeSearch? session = _searches[keyword];
    if (page == 1 || session == null) {
      final html = await this.page('/results', query: {'search_query': keyword, 'sp': 'EgJAAQ=='});
      final initial = YouTubePage.objectAfter(html, 'var ytInitialData =');
      if (initial == null) throw StateError('YouTube search response missing');
      session = _YouTubeSearch(YouTubePage.context(html));
      session.add(initial);
      if (_searches.length >= 8) _searches.remove(_searches.keys.first);
      _searches[keyword] = session;
    }
    final size = pageSize.clamp(1, 100);
    final start = session.consumed;
    var emptyPages = 0;
    while (session.rooms.length - start < size && session.continuation != null) {
      final token = session.continuation!;
      if (!session.usedTokens.add(token)) throw StateError('YouTube search cursor repeated');
      final response = await api('search', {'context': session.context, 'continuation': token});
      final previousCount = session.rooms.length;
      session.add(response);
      emptyPages = session.rooms.length == previousCount ? emptyPages + 1 : 0;
      if (emptyPages >= 3 && session.continuation != null) {
        throw StateError('YouTube search returned no live results across successive pages');
      }
    }
    final end = (start + size).clamp(0, session.rooms.length);
    session.consumed = end;
    return session.rooms.sublist(start, end);
  }

  static List<LiveRoom> parseSearch(dynamic response) {
    final rooms = <LiveRoom>[];
    for (final video in YouTubePage.renderers(response, 'videoRenderer')) {
      final live = YouTubePage.renderers(
        video['badges'],
        'metadataBadgeRenderer',
      ).any((badge) => badge['style'] == 'BADGE_STYLE_TYPE_LIVE_NOW');
      if (!live || video['videoId'] == null) continue;
      final videoId = video['videoId'].toString();
      rooms.add(
        LiveRoom(
          platform: 'youtube',
          roomId: videoId,
          title: YouTubePage.text(video['title']),
          nick: YouTubePage.text(video['ownerText'] ?? video['longBylineText']),
          cover: YouTubePage.thumbnail(video['thumbnail']),
          avatar: YouTubePage.thumbnail(
            video['channelThumbnailSupportedRenderers']?['channelThumbnailWithLinkRenderer']?['thumbnail'],
          ),
          status: true,
          liveStatus: LiveStatus.live,
          link: 'https://www.youtube.com/watch?v=$videoId',
          danmakuData: videoId,
          data: {'videoId': videoId},
        ),
      );
    }
    return rooms;
  }

  /// Keeps video IDs case-sensitive; channel/@handle links retain channel identity in favourites.
  static String? roomIdentity(String input) {
    final value = input.trim();
    if (RegExp(r'^[\w-]{11}$').hasMatch(value) ||
        RegExp(r'^@[\w.\-]+$').hasMatch(value) ||
        RegExp(r'^channel/UC[\w-]+$').hasMatch(value)) {
      return value;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !{'https', 'http'}.contains(uri.scheme)) return null;
    final segments = uri.pathSegments;
    if (uri.host == 'youtu.be' && segments.length == 1) return roomIdentity(segments.single);
    if (!(uri.host == 'youtube.com' || uri.host.endsWith('.youtube.com'))) return null;
    if (uri.path == '/watch') {
      final video = uri.queryParameters['v'] ?? '';
      return RegExp(r'^[\w-]{11}$').hasMatch(video) ? video : null;
    }
    if (segments.isNotEmpty &&
        segments.first.startsWith('@') &&
        (segments.length == 1 || (segments.length == 2 && segments[1] == 'live'))) {
      return roomIdentity(segments.first);
    }
    if (segments.length >= 2 &&
        segments.first == 'channel' &&
        (segments.length == 2 || (segments.length == 3 && segments.last == 'live'))) {
      return roomIdentity('channel/${segments[1]}');
    }
    if (segments.length == 2 && {'live', 'embed'}.contains(segments.first)) return roomIdentity(segments.last);
    return null;
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) async {
    final identity = roomIdentity(roomId);
    if (identity == null) throw ArgumentError('Invalid YouTube video/channel');
    final html = identity.startsWith('@') || identity.startsWith('channel/')
        ? await page('/$identity/live')
        : await page('/watch', query: {'v': identity});
    final player = YouTubePage.objectAfter(html, 'var ytInitialPlayerResponse =');
    if (player == null) throw StateError('YouTube player response missing');
    final video = player['videoDetails'] as Map?;
    final status = player['playabilityStatus'] as Map? ?? {};
    if (video == null) {
      if (status['status'] == 'LIVE_STREAM_OFFLINE') {
        return LiveRoom(
          platform: id,
          roomId: identity,
          status: false,
          liveStatus: LiveStatus.offline,
          nick: identity,
          title: YouTubePage.text(status['reason']),
        );
      }
      throw StateError(
        'YouTube: ${YouTubePage.text(status['reason']).isEmpty ? 'video unavailable' : YouTubePage.text(status['reason'])}',
      );
    }
    final broadcast = player['microformat']?['playerMicroformatRenderer']?['liveBroadcastDetails'];
    final live = broadcast?['isLiveNow'] == true || video['isLive'] == true;
    final videoId = video['videoId'].toString();
    return LiveRoom(
      platform: id,
      roomId: identity,
      userId: video['channelId']?.toString(),
      title: video['title']?.toString(),
      nick: video['author']?.toString(),
      cover: YouTubePage.thumbnail(video['thumbnail']),
      avatar: '',
      status: live,
      liveStatus: live ? LiveStatus.live : LiveStatus.offline,
      link: 'https://www.youtube.com/watch?v=$videoId',
      introduction: '',
      notice: '',
      danmakuData: videoId,
      data: {'videoId': videoId},
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.status != true) return [];
    final videoId = (detail.data as Map)['videoId'];
    final player = await api('player', {
      'videoId': videoId,
      'context': {'client': androidClient},
      'playbackContext': {
        'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
    });
    final status = player['playabilityStatus'];
    if (status?['status'] != 'OK') throw StateError('YouTube: ${status?['reason'] ?? 'playback unavailable'}');
    final url = player['streamingData']?['hlsManifestUrl']?.toString();
    if (url == null) {
      throw StateError('YouTube did not provide a live HLS stream; restricted streams are not supported');
    }
    final playlist = await HttpClient.instance.getText(url, header: headers);
    // HLS contains muxed audio+video. Adaptive video-only URLs are deliberately excluded.
    final qualities = TwitchSite.parseMasterPlaylist(playlist, masterUri: Uri.parse(url));
    if (qualities.isEmpty) throw StateError('YouTube live HLS variants missing');
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      List<String>.from(quality.data as List);

  @override
  Future<bool> getLiveStatus({required String platform, required String roomId}) async =>
      (await getRoomDetail(roomId: roomId, platform: platform)).status == true;
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) =>
      getRoomDetail(roomId: roomId, platform: platform);
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) =>
      getRoomDetail(roomId: roomId, platform: platform);
}

class _YouTubeSearch {
  _YouTubeSearch(this.context);
  final Map<String, dynamic> context;
  final rooms = <LiveRoom>[];
  final seen = <String?>{};
  final usedTokens = <String>{};
  int consumed = 0;
  String? continuation;
  void add(dynamic response) {
    rooms.addAll(YouTubeSite.parseSearch(response).where((room) => seen.add(room.roomId)));
    continuation = YouTubePage.renderers(
      response,
      'continuationCommand',
    ).map((command) => command['token']?.toString()).whereType<String>().firstOrNull;
  }
}
