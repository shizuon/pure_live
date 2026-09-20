import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/favorite_room_controller.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/danmaku/kick_danmaku.dart';
import 'package:pure_live/core/danmaku/youtube_danmaku.dart';
import 'package:pure_live/core/site/kick/kick_site.dart';
import 'package:pure_live/core/site/youtube/youtube_page.dart';
import 'package:pure_live/core/site/youtube/youtube_site.dart';
import 'package:pure_live/modules/search/web_search_room_parser.dart';

class FixtureKick extends KickSite {
  FixtureKick(this.respond);
  final dynamic Function(String, Map<String, dynamic>?) respond;
  @override
  Future<dynamic> request(String path, {Map<String, dynamic>? query}) async => respond(path, query);
}

class FixtureKickChat extends KickDanmaku {
  int calls = 0;
  Completer<dynamic>? pending;
  @override
  Future<dynamic> connectionConfig(Map args, CancelToken cancel, String clientId) async {
    calls++;
    if (pending != null) return pending!.future;
    throw StateError('network');
  }
}

class FixtureYouTube extends YouTubeSite {
  String html = '';
  dynamic response;
  int requests = 0;
  @override
  Future<String> page(String path, {Map<String, dynamic>? query}) async => html;
  @override
  Future<dynamic> api(String operation, Map<String, dynamic> body) async {
    requests++;
    return response;
  }
}

String watchPage({bool chat = true}) =>
    '''
ytcfg.set(${jsonEncode({
      'INNERTUBE_CONTEXT': {
        'client': {'clientName': 'WEB', 'clientVersion': 'test'},
      },
    })});
var ytInitialData = ${jsonEncode(chat ? {
            'liveChatRenderer': {
              'continuations': [
                {
                  'reloadContinuationData': {'continuation': 'first'},
                },
              ],
            },
          } : {})};</script>
''';

Map<String, dynamic> chatResponse({String token = 'next'}) => {
  'continuationContents': {
    'liveChatContinuation': {
      'actions': [
        {
          'addChatItemAction': {
            'item': {
              'liveChatTextMessageRenderer': {
                'id': 'message-1',
                'authorName': {'simpleText': 'Viewer'},
                'message': {
                  'runs': [
                    {'text': 'hello'},
                  ],
                },
              },
            },
          },
        },
      ],
      'continuations': [
        {
          'timedContinuationData': {'continuation': token, 'timeoutMs': 2000},
        },
      ],
    },
  },
};

class FixtureChat extends YouTubeDanmaku {
  int opens = 0;
  int polls = 0;
  bool fail = false;
  bool chatEnabled = true;
  Completer<dynamic>? pending;
  @override
  Future<String> watch(String videoId, CancelToken cancel) async {
    opens++;
    return watchPage(chat: chatEnabled);
  }

  @override
  Future<dynamic> poll(String continuation, CancelToken cancel) async {
    polls++;
    if (fail) throw StateError('network');
    return pending == null ? chatResponse() : pending!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('catalogue migration adds only new platforms and preserves hidden old platforms', () async {
    final directory = await Directory.systemTemp.createTemp('global-platform-settings-');
    Hive.init(directory.path);
    await HivePrefUtil.init();
    try {
      await Hive.box('app_settings').put('siteCatalogMigration', 2);
      await Hive.box('app_settings').put('hotAreasList', ['twitch']);
      final settings = FavoriteRoomController();
      settings.onInit();
      expect(settings.hotAreasList, ['twitch', 'kick', 'youtube']);
      settings.hotAreasList.remove('kick');
      settings.onInit();
      expect(settings.hotAreasList, ['twitch', 'youtube']);
      settings.onClose();
      // Hive-backed Rx workers deliver changes asynchronously.
      await Future<void>.delayed(Duration.zero);
      await Hive.box('app_settings').flush();
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });

  test('YouTube channel favourites retain identity when the current video changes', () async {
    final site = FixtureYouTube()
      ..html =
          'var ytInitialPlayerResponse = ${jsonEncode({
            'playabilityStatus': {'status': 'OK'},
            'videoDetails': {'videoId': 'aBcDeFgH_12', 'isLive': true, 'author': 'Demo', 'title': 'Live'},
          })};</script>';
    final room = await site.getRoomDetail(roomId: '@Demo', platform: 'youtube');
    expect(room.roomId, '@Demo');
    expect(room.status, true);
    expect(room.danmakuData, 'aBcDeFgH_12');
  });

  test('YouTube pagination preserves overflow and refresh resets continuation state', () async {
    Map renderer(String id) => {
      'videoRenderer': {
        'videoId': id,
        'badges': [
          {
            'metadataBadgeRenderer': {'style': 'BADGE_STYLE_TYPE_LIVE_NOW'},
          },
        ],
      },
    };
    final initial = {
      'contents': [renderer('first'), renderer('second')],
      'continuationCommand': {'token': 'cursor'},
    };
    final site = FixtureYouTube()
      ..html =
          'ytcfg.set({"INNERTUBE_CONTEXT":{"client":{}}});'
          'var ytInitialData = ${jsonEncode(initial)};</script>'
      ..response = {
        'contents': [renderer('second'), renderer('third')],
      };
    expect((await site.searchRooms('news', pageSize: 1)).single.roomId, 'first');
    expect((await site.searchRooms('news', page: 2, pageSize: 1)).single.roomId, 'second');
    expect(site.requests, 0);
    expect((await site.searchRooms('news', page: 3, pageSize: 1)).single.roomId, 'third');
    expect(site.requests, 1);
    expect(await site.searchRooms('news', page: 4, pageSize: 1), isEmpty);
    expect((await site.searchRooms('news', pageSize: 1)).single.roomId, 'first');
  });

  test('eleven-character search terms are not mistaken for YouTube video IDs', () async {
    final site = FixtureYouTube()
      ..html =
          'ytcfg.set({"INNERTUBE_CONTEXT":{"client":{}}});'
          'var ytInitialData = {"contents":[]};</script>';
    expect(await site.searchRooms('livestreams'), isEmpty);
  });

  test('Kick config failures retry every 15 seconds and stop releases retry timer', () {
    fakeAsync((async) {
      final chat = FixtureKickChat();
      final notices = <String>[];
      chat.onClose = notices.add;
      chat.start({'channelId': '1', 'chatroomId': '2'});
      async.flushMicrotasks();
      expect(chat.calls, 1);
      expect(notices.single, contains('正在尝试重连'));
      async.elapse(const Duration(seconds: 15));
      async.flushMicrotasks();
      expect(chat.calls, 2);
      chat.stop();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      expect(chat.calls, 2);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('Kick config response cannot open a socket after room exit', () {
    fakeAsync((async) {
      final chat = FixtureKickChat()..pending = Completer<dynamic>();
      final notices = <String>[];
      chat.onClose = notices.add;
      chat.start({'channelId': '1', 'chatroomId': '2'});
      async.flushMicrotasks();
      chat.stop();
      async.flushMicrotasks();
      chat.pending!.complete({
        'data': {'connections': []},
      });
      async.flushMicrotasks();
      expect(notices, isEmpty);
      expect(chat.isConnected, false);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('YouTube does not reschedule polling when onReady closes the session', () {
    fakeAsync((async) {
      final chat = FixtureChat();
      var messages = 0;
      chat.onReady = () {
        chat.stop();
      };
      chat.onMessage = (_) => messages++;
      chat.start('aBcDeFgH_12');
      async.flushMicrotasks();
      expect(messages, 0);
      expect(async.pendingTimers, isEmpty);
    });
  });
  test('Kick keeps offline channels offline even when a persistent playback URL exists', () {
    final room = KickSite.parseChannel({
      'slug': 'demo',
      'playback_url': 'https://cdn.test/live.m3u8',
      'livestream': null,
      'user': {'username': 'Demo'},
    });
    expect(room.status, false);
    expect(room.nick, 'Demo');
  });

  test('Kick directory preserves surplus rows returned for small requested pages', () async {
    var calls = 0;
    final site = FixtureKick((path, query) {
      calls++;
      expect(path, '/stream/livestreams/en');
      expect(query!['page'], 1);
      return {
        'next_page_url': null,
        'data': List.generate(
          5,
          (i) => {
            'session_title': 'Stream $i',
            'is_live': true,
            'viewer_count': i,
            'channel': {
              'slug': 'room$i',
              'user': {'username': 'Room $i'},
            },
          },
        ),
      };
    });
    final first = await site.getRecommendRooms(pageSize: 2);
    final second = await site.getRecommendRooms(page: 2, pageSize: 2);
    final third = await site.getRecommendRooms(page: 3, pageSize: 2);
    expect([...first, ...second, ...third].map((room) => room.roomId), ['room0', 'room1', 'room2', 'room3', 'room4']);
    expect(calls, 1);
  });

  test('Kick search has one bounded result set and preserves live flags', () async {
    final site = FixtureKick((path, query) {
      expect(query, {'searched_word': 'demo', 'type': 'channel'});
      return {
        'channels': [
          {'slug': 'demo', 'isLive': true, 'user': {}},
        ],
      };
    });
    expect((await site.searchRooms('demo')).single.status, true);
    expect(await site.searchRooms('demo', page: 2), isEmpty);
  });

  test('Kick directory filters by category slug rather than silently ignored numeric ID', () async {
    final site = FixtureKick((path, query) {
      expect(query!['subcategory'], 'counter-strike-2');
      return {'data': [], 'next_page_url': null};
    });
    await site.getCategoryRooms(LiveArea(areaId: '27', shortName: 'counter-strike-2'));
  });

  test('YouTube embedded JSON survives braces and escaped quotes inside strings', () {
    final data = {
      'title': 'a } { "quote" \\ string',
      'nested': {
        'list': [1, 2],
      },
    };
    expect(YouTubePage.objectAfter('x;var ytInitialData = ${jsonEncode(data)};</script>', 'var ytInitialData ='), data);
    expect(YouTubePage.objectAfter('unrelated', 'var ytInitialData ='), isNull);
  });

  test('YouTube URLs preserve ID case and reject non-room routes and foreign hosts', () {
    const id = 'aBcDeFgH_12';
    for (final url in [
      'https://youtu.be/$id',
      'https://www.youtube.com/watch?v=$id',
      'https://www.youtube.com/live/$id',
    ]) {
      expect(WebSearchRoomParser.parse(url)?.roomId, id);
    }
    expect(WebSearchRoomParser.parse('https://www.youtube.com/@NBCNews/live')?.roomId, '@NBCNews');
    expect(WebSearchRoomParser.parse('https://youtube.com.evil.test/watch?v=$id'), isNull);
    expect(WebSearchRoomParser.parse('https://youtube.com/results?search_query=test'), isNull);
    expect(WebSearchRoomParser.parse('https://kick.com/categories'), isNull);
    expect(WebSearchRoomParser.parse('https://kick.com/demo/videos/123'), isNull);
  });

  test('YouTube live search excludes recordings and upcoming items', () {
    Map video(String id, String badge) => {
      'videoRenderer': {
        'videoId': id,
        'title': {
          'runs': [
            {'text': 'live } title'},
          ],
        },
        'badges': [
          {
            'metadataBadgeRenderer': {'style': badge},
          },
        ],
      },
    };
    final rooms = YouTubeSite.parseSearch({
      'contents': [video('aBcDeFgH_12', 'BADGE_STYLE_TYPE_LIVE_NOW'), video('recording12', 'BADGE_STYLE_TYPE_SIMPLE')],
    });
    expect(rooms.single.roomId, 'aBcDeFgH_12');
    expect(rooms.single.title, 'live } title');
  });

  test('Kick chat parser preserves identity, timestamp and color', () {
    final message = KickDanmaku.parseMessage({
      'event': r'App\Events\ChatMessageEvent',
      'data': jsonEncode({
        'id': 'm1',
        'content': 'hello',
        'created_at': '2026-09-21T00:00:00Z',
        'sender': {
          'id': 23,
          'username': 'Demo',
          'identity': {'color': '#12ab34'},
        },
      }),
    });
    expect(message?.messageId, 'm1');
    expect(message?.userId, '23');
    expect(message?.color.toString(), '#12ab34');
    expect(message?.sentAt, isNotNull);
    expect(KickDanmaku.parseMessage({'event': 'pusher:pong'}), isNull);
  });

  test('YouTube follows poll interval, deduplicates replay and cancels on stop', () {
    fakeAsync((async) {
      final chat = FixtureChat();
      final messages = <String>[];
      chat.onMessage = (message) => messages.add(message.message);
      chat.start('aBcDeFgH_12');
      async.flushMicrotasks();
      expect(chat.isConnected, true);
      expect(messages, ['hello']);
      expect(chat.polls, 1);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(chat.polls, 2);
      expect(messages, ['hello']);
      chat.stop();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      expect(chat.polls, 2);
      expect(chat.isConnected, false);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('YouTube discards an in-flight response after leaving the room', () {
    fakeAsync((async) {
      final chat = FixtureChat()..pending = Completer<dynamic>();
      var messages = 0;
      chat.onMessage = (_) => messages++;
      chat.start('aBcDeFgH_12');
      async.flushMicrotasks();
      chat.stop();
      async.flushMicrotasks();
      chat.pending!.complete(chatResponse());
      async.flushMicrotasks();
      expect(messages, 0);
      expect(chat.isConnected, false);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('YouTube transport failure retries after 15 seconds with a fresh continuation', () {
    fakeAsync((async) {
      final chat = FixtureChat()..fail = true;
      final notices = <String>[];
      chat.onClose = notices.add;
      chat.start('aBcDeFgH_12');
      async.flushMicrotasks();
      expect(chat.isConnected, false);
      expect(notices.single, contains('正在尝试重连'));
      async.elapse(const Duration(seconds: 14));
      expect(chat.opens, 1);
      chat.fail = false;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(chat.opens, 2);
      expect(chat.isConnected, true);
      chat.stop();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('YouTube disabled chat reports unavailable without an endless reconnect timer', () {
    fakeAsync((async) {
      final chat = FixtureChat()..chatEnabled = false;
      final notices = <String>[];
      chat.onClose = notices.add;
      chat.start('aBcDeFgH_12');
      async.flushMicrotasks();
      expect(notices.single, contains('未开放'));
      expect(chat.polls, 0);
      expect(async.pendingTimers, isEmpty);
    });
  });
}
