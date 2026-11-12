import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/douyin/douyin_site.dart';
import 'package:pure_live/common/models/live_area.dart';

class _Site extends DouyinSite {
  @override
  Future<Map<String, dynamic>> getRequestHeaders() async => headers;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps the official category order and game partitions with an all entry', () async {
    // Public categoryData from https://live.douyin.com/ on 2026-11-12.
    const categoryData = [
      {
        'partition': {'id_str': '101', 'type': 4, 'title': '聊天'},
        'sub_partition': [],
      },
      {
        'partition': {'id_str': '102', 'type': 4, 'title': '音乐'},
        'sub_partition': [],
      },
      {
        'partition': {'id_str': '103', 'type': 4, 'title': '游戏'},
        'sub_partition': [
          {
            'partition': {'id_str': '1011032', 'type': 1, 'title': '三角洲行动'},
            'sub_partition': [],
          },
          {
            'partition': {'id_str': '1010045', 'type': 1, 'title': '王者荣耀'},
            'sub_partition': [],
          },
          {
            'partition': {'id_str': '1010017', 'type': 1, 'title': '无畏契约'},
            'sub_partition': [],
          },
          {
            'partition': {'id_str': '1010014', 'type': 1, 'title': '英雄联盟'},
            'sub_partition': [],
          },
          {
            'partition': {'id_str': '1010032', 'type': 1, 'title': '和平精英'},
            'sub_partition': [],
          },
          {
            'partition': {'id_str': '1010146', 'type': 1, 'title': 'QQ飞车端游'},
            'sub_partition': [],
          },
          {
            'partition': {'id_str': '1010037', 'type': 1, 'title': '穿越火线'},
            'sub_partition': [],
          },
          {
            'partition': {'id_str': '1010026', 'type': 1, 'title': '绝地求生'},
            'sub_partition': [],
          },
          {
            'partition': {'id_str': '1010042', 'type': 1, 'title': '火影忍者手游'},
            'sub_partition': [],
          },
        ],
      },
      {
        'partition': {'id_str': '104', 'type': 4, 'title': '二次元'},
        'sub_partition': [],
      },
      {
        'partition': {'id_str': '105', 'type': 4, 'title': '舞蹈'},
        'sub_partition': [],
      },
      {
        'partition': {'id_str': '106', 'type': 4, 'title': '文化'},
        'sub_partition': [],
      },
      {
        'partition': {'id_str': '107', 'type': 4, 'title': '生活'},
        'sub_partition': [],
      },
      {
        'partition': {'id_str': '108', 'type': 4, 'title': '运动'},
        'sub_partition': [],
      },
    ];
    final payload = jsonEncode({'pathname': '/', 'categoryData': categoryData});
    final page = '<script>self.__next_f.push([1,${jsonEncode(payload)}])</script>';
    final previous = HttpClient.instance.dio;
    final fixture = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.uri.host, 'live.douyin.com');
            expect(options.uri.path, '/');
            handler.resolve(Response(requestOptions: options, data: page));
          },
        ),
      );
    HttpClient.instance.dio = fixture;
    try {
      final categories = await _Site().getCategores(1, 30);

      expect(categories.map((category) => category.name), ['聊天', '音乐', '游戏', '二次元', '舞蹈', '文化', '生活', '运动']);
      expect(categories.map((category) => category.id), [
        '101,4',
        '102,4',
        '103,4',
        '104,4',
        '105,4',
        '106,4',
        '107,4',
        '108,4',
      ]);
      for (final category in categories) {
        expect(category.children.first.areaName, '全部');
        expect(category.children.first.areaId, category.id);
        expect(category.children.first.areaType, category.id);
        expect(category.children.first.typeName, category.name);
      }
      final games = categories[2].children;
      expect(games.map((area) => area.areaName), [
        '全部',
        '三角洲行动',
        '王者荣耀',
        '无畏契约',
        '英雄联盟',
        '和平精英',
        'QQ飞车端游',
        '穿越火线',
        '绝地求生',
        '火影忍者手游',
      ]);
      expect(games.map((area) => area.areaId), [
        '103,4',
        '1011032,1',
        '1010045,1',
        '1010017,1',
        '1010014,1',
        '1010032,1',
        '1010146,1',
        '1010037,1',
        '1010026,1',
        '1010042,1',
      ]);
      expect(games.every((area) => area.areaType == '103,4' && area.typeName == '游戏'), isTrue);
      expect(
        categories.where((category) => category.id != '103,4').every((category) => category.children.length == 1),
        isTrue,
      );
    } finally {
      HttpClient.instance.dio = previous;
      fixture.close(force: true);
    }
  });

  test('category room requests honor the requested page size and official partition pair', () async {
    final previous = HttpClient.instance.dio;
    final requests = <Uri>[];
    final fixture = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri);
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'status_code': 0,
                  'data': {'data': <dynamic>[]},
                },
              ),
            );
          },
        ),
      );
    HttpClient.instance.dio = fixture;
    try {
      final site = _Site();
      final area = LiveArea(areaId: '103,4', areaName: '游戏');
      await site.getCategoryRooms(area, page: 1, pageSize: 30);
      await site.getCategoryRooms(area, page: 2, pageSize: 30);
      await site.getCategoryRooms(area, page: 3, pageSize: 12);

      expect(requests.map((uri) => uri.queryParameters['count']), ['30', '30', '12']);
      expect(requests.map((uri) => uri.queryParameters['offset']), ['0', '30', '24']);
      for (final uri in requests) {
        expect(uri.path, '/webcast/web/partition/detail/room/v2/');
        expect(uri.queryParameters['partition'], '103');
        expect(uri.queryParameters['partition_type'], '4');
      }
    } finally {
      HttpClient.instance.dio = previous;
      fixture.close(force: true);
    }
  });
}
