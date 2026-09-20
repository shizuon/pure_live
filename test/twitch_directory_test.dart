import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/core/site/twitch/twitch_site.dart';

class FixtureTwitch extends TwitchSite {
  FixtureTwitch(this.respond);
  final dynamic Function(dynamic) respond;
  final requests = <dynamic>[];

  @override
  Future<dynamic> getGplResponse(String request) async {
    final decoded = jsonDecode(request);
    requests.add(decoded);
    return respond(decoded);
  }
}

Map<String, dynamic> connection(List<dynamic> edges, {bool more = false}) => {
  'edges': edges,
  'pageInfo': {'hasNextPage': more},
};

void main() {
  final cs = LiveArea(shortName: 'counter-strike', areaName: 'Counter-Strike');
  test('CS directory does not exclude French croissantstrike or require optional artwork', () async {
    final site = FixtureTwitch((request) {
      expect(request[0]['variables']['options']['broadcasterLanguages'], isEmpty);
      expect(request[0]['variables']['limit'], 12);
      return [
        {
          'data': {
            'game': {
              'streams': connection([
                {'node': null},
                {
                  'cursor': 'end',
                  'node': {
                    'broadcaster': {'login': 'croissantstrike', 'displayName': 'CroissantStrike'},
                    'title': 'StarLadder final',
                    'viewersCount': 18667,
                  },
                },
              ]),
            },
          },
        },
      ];
    });
    final rooms = await site.getCategoryRooms(cs, pageSize: 12);
    expect(rooms.single.roomId, 'croissantstrike');
    expect(rooms.single.danmakuData, 'croissantstrike');
    expect(rooms.single.area, 'Counter-Strike');
    expect(rooms.single.avatar, '');
  });

  test('catalogue includes untagged games and follows cursor even after a short page', () async {
    final site = FixtureTwitch((request) {
      expect(request['operationName'], 'BrowsePage_AllDirectories');
      expect(request['variables']['options']['tags'], isEmpty);
      final next = request['variables']['cursor'] != null;
      return {
        'data': {
          'directoriesWithTags': connection([
            {
              'cursor': next ? 'last' : 'next',
              'node': {
                'id': next ? '2' : '1',
                'displayName': next ? 'Untagged' : 'Counter-Strike',
                'slug': next ? 'untagged' : 'counter-strike',
              },
            },
          ], more: !next),
        },
      };
    });
    final categories = await site.getCategores(1, 1000);
    expect(categories.single.children.map((area) => area.shortName), ['counter-strike', 'untagged']);
    expect(site.requests, hasLength(2));
  });

  test('refresh invalidates later cursors even when new first page is empty', () async {
    var count = 0;
    final site = FixtureTwitch((_) {
      count++;
      return [
        {
          'data': {
            'game': {
              'streams': connection(
                count > 1
                    ? []
                    : [
                        {
                          'cursor': 'old',
                          'node': {
                            'broadcaster': {'login': 'demo'},
                          },
                        },
                      ],
                more: count == 1,
              ),
            },
          },
        },
      ];
    });
    await site.getCategoryRooms(cs);
    expect(site.getCursor('getCategoryRooms', 'counter-strike', 2), 'old');
    await site.getCategoryRooms(cs);
    expect(await site.getCategoryRooms(cs, page: 2), isEmpty);
    expect(count, 2);
  });

  test('channel URL directly resolves without relying on search index', () async {
    final site = FixtureTwitch((request) {
      expect(request, isA<List>());
      expect(request[0]['variables']['login'], 'croissantstrike');
      return [
        {
          'data': {
            'userOrError': {'login': 'croissantstrike', 'displayName': 'CroissantStrike'},
          },
        },
        {
          'data': {
            'user': {
              'stream': {'type': 'live', 'viewersCount': 123},
            },
          },
        },
      ];
    });
    final rooms = await site.searchRooms('https://www.twitch.tv/croissantstrike');
    expect(rooms.single.roomId, 'croissantstrike');
    expect(rooms.single.status, true);
    expect(await site.searchRooms('https://www.twitch.tv/croissantstrike', page: 2), isEmpty);
    expect(site.requests, hasLength(1));
  });

  test('channel parser rejects foreign hosts and directory URLs', () {
    expect(TwitchSite.channelLogin('CroissantStrike'), 'croissantstrike');
    expect(TwitchSite.channelLogin('https://twitch.tv.evil.test/name'), isNull);
    expect(TwitchSite.channelLogin('https://www.twitch.tv/directory'), isNull);
    expect(TwitchSite.channelLogin('https://www.twitch.tv/videos/123'), isNull);
  });
}
