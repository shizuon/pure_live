import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/danmaku/kick_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/twitch/twitch_site.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/common/index.dart' show i18n;
import 'package:pure_live/model/live_play_quality.dart';

class KickSite extends LiveSite implements LiveSiteRoomRefresher, LiveSiteRecordRoomResolver {
  KickSite() {
    id = 'kick';
    name = 'Kick';
  }

  // Kick rejects the stale Chrome version used by the Twitch adapter. Keep
  // platform headers independent; this generic UA is verified with Dio.
  static const headers = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://kick.com/'};
  final _directories = <String, _KickDirectory>{};

  Future<dynamic> request(String path, {Map<String, dynamic>? query}) =>
      HttpClient.instance.getJson('https://kick.com$path', header: headers, queryParameters: query);

  @override
  LiveDanmaku getDanmaku() => KickDanmaku();

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    final groups = <String, LiveCategory>{};
    final seen = <String>{};
    // This endpoint ignores limit and returns 32 entries across hundreds of
    // pages. The Kick page uses fixed remote paging, never a complete-catalog
    // prefetch before first paint.
    if (page < 1) return [];
    final response = await request('/api/v1/subcategories', query: {'page': page, 'limit': 32});
    if (response is! Map || response['data'] is! List) throw StateError('Kick categories missing');
    final currentPage = int.tryParse(response['current_page']?.toString() ?? '');
    if (currentPage != null && currentPage != page) throw StateError('Kick category page did not advance');
    final perPage = int.tryParse(response['per_page']?.toString() ?? '');
    if (perPage != null && perPage != 32) throw StateError('Kick category page size changed');
    final rows = response['data'] as List;
    for (final row in rows.whereType<Map>()) {
      final areaId = row['id']?.toString() ?? '';
      final slug = row['slug']?.toString().trim() ?? '';
      if (areaId.isEmpty || slug.isEmpty) continue;
      if (!seen.add(areaId)) continue;
      final parent = row['category'] as Map? ?? {};
      final groupId = (parent['id'] ?? row['category_id'] ?? 'all').toString();
      final group = groups.putIfAbsent(
        groupId,
        () => LiveCategory(id: groupId, name: (parent['name'] ?? 'Kick').toString(), children: []),
      );
      group.children.add(
        LiveArea(
          platform: id,
          areaId: areaId,
          areaName: row['name']?.toString(),
          shortName: slug,
          areaType: groupId,
          typeName: group.name,
          areaPic: row['banner'] is Map ? row['banner']['url']?.toString() ?? '' : '',
        ),
      );
    }
    if (seen.length != rows.length) {
      throw StateError('Kick category page contains incomplete or duplicate entries');
    }
    return groups.values.toList();
  }

  Future<List<LiveRoom>> _directory(int page, int pageSize, {String? category}) async {
    final key = category ?? '';
    if (page == 1) _directories.remove(key);
    if (_directories.length >= 8 && !_directories.containsKey(key)) _directories.remove(_directories.keys.first);
    final session = _directories.putIfAbsent(key, _KickDirectory.new);
    final size = pageSize.clamp(1, 100);
    // Kick rounds small limits up to five. Preserve all returned rows instead
    // of losing the tail when a desktop page needs only one more item.
    while (session.pending.length < size && session.hasMore) {
      final response = await request(
        '/stream/livestreams/en',
        query: {'page': session.page, 'limit': 30, 'sort': 'desc', if (category != null) 'subcategory': category},
      );
      var added = 0;
      for (final row in response['data'] as List) {
        final channel = Map<String, dynamic>.from(row['channel'] as Map);
        channel['livestream'] = row;
        final room = parseChannel(channel);
        if (session.seen.add(room.roomId)) {
          session.pending.add(room);
          added++;
        }
      }
      session.page++;
      session.hasMore = response['next_page_url'] != null;
      if (added == 0 && session.hasMore) throw StateError('Kick directory did not advance');
    }
    final result = session.pending.take(size).toList();
    session.pending.removeRange(0, result.length);
    return result;
  }

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) => _directory(page, pageSize);

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) =>
      _directory(page, pageSize, category: category.shortName);

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    // Kick's public search returns a bounded result set, not a page cursor.
    if (page != 1) return [];
    final uri = Uri.tryParse(keyword.trim());
    if (uri != null &&
        uri.hasScheme &&
        (uri.host == 'kick.com' || uri.host == 'www.kick.com') &&
        uri.pathSegments.length == 1) {
      return [await getRoomDetail(roomId: uri.pathSegments.single, platform: id)];
    }
    final result = await request('/api/search', query: {'searched_word': keyword, 'type': 'channel'});
    return (result['channels'] as List).whereType<Map>().map(parseChannel).toList();
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(roomId)) throw ArgumentError('Invalid Kick channel');
    final response = await request('/api/v2/channels/${Uri.encodeComponent(roomId.toLowerCase())}');
    if (response is! Map || response['slug'] == null) throw StateError('Kick channel metadata missing');
    return parseChannel(response);
  }

  static LiveRoom parseChannel(Map channel) {
    final slug = channel['slug']?.toString() ?? '';
    final user = channel['user'] as Map? ?? {};
    final stream = channel['livestream'] as Map?;
    final live =
        channel['is_banned'] != true && (stream != null ? stream['is_live'] != false : channel['isLive'] == true);
    final categories =
        (stream?['categories'] ?? channel['recent_categories'] ?? channel['recentCategories']) as List? ?? [];
    final thumbnail = stream?['thumbnail'];
    final viewers = (stream?['viewer_count'] ?? stream?['viewers'])?.toString() ?? '';
    return LiveRoom(
      platform: 'kick',
      roomId: slug,
      userId: channel['user_id']?.toString(),
      title: (stream?['session_title'] ?? user['username'] ?? slug).toString(),
      nick: (user['username'] ?? slug).toString(),
      avatar: (user['profile_pic'] ?? user['profilepic'] ?? '').toString(),
      cover: (thumbnail is Map ? thumbnail['url'] : thumbnail)?.toString() ?? '',
      watching: viewers,
      onlineViewers: viewers,
      audienceMetricType: AudienceMetricType.onlineViewers,
      area: categories.isEmpty ? '' : categories.first['name']?.toString(),
      status: live,
      liveStatus: live ? LiveStatus.live : LiveStatus.offline,
      link: 'https://kick.com/$slug',
      introduction: user['bio']?.toString() ?? '',
      notice: '',
      danmakuData: channel['chatroom']?['id'] == null
          ? null
          : {'channelId': channel['id'].toString(), 'chatroomId': channel['chatroom']['id'].toString()},
      data: channel['playback_url'],
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.status != true) return [];
    final uri = Uri.tryParse(detail.data?.toString() ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) throw StateError('Kick playback URL missing');
    final playlist = await HttpClient.instance.getText(uri.toString(), header: headers);
    final qualities = TwitchSite.parseMasterPlaylist(playlist, masterUri: uri);
    if (qualities.isEmpty && playlist.trimLeft().startsWith('#EXTM3U') && playlist.contains('#EXTINF:')) {
      return [
        LivePlayQuality(quality: i18n('quality_unconfirmed'), id: 'single-stream', data: [uri.toString()]),
      ];
    }
    if (qualities.isEmpty) throw StateError('Kick returned an invalid HLS playlist');
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

class _KickDirectory {
  int page = 1;
  bool hasMore = true;
  final pending = <LiveRoom>[];
  final seen = <String?>{};
}
