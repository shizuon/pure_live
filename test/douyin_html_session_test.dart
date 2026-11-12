import 'dart:convert';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/cookie_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/douyin/douyin_site.dart';
import 'package:pure_live/get/get.dart';

class _Settings extends SettingsService {
  @override
  // ignore: must_call_super -- no services/network in account fixture.
  void onInit() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late io.Directory temp;
  late CookieSettingsController cookies;

  setUp(() async {
    temp = await io.Directory.systemTemp.createTemp('douyin-html-session');
    Hive.init(temp.path);
    await HivePrefUtil.init();
    cookies = Get.put(CookieSettingsController());
    Get.put<SettingsService>(_Settings());
  });

  tearDown(() async {
    Get.reset();
    DouyinSite.cookie = '';
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('HTML fallback keeps the account session and adds missing page cookies', () async {
    cookies.setAccountCookie('douyin', 'sessionid=account; ttwid=account-visitor');
    final previous = HttpClient.instance.dio;
    final requests = <RequestOptions>[];
    final state = {
      'appStore': <String, dynamic>{},
      'userStore': {
        'odin': {'user_unique_id': 'fixture-user'},
      },
      'roomStore': {
        'roomInfo': {
          'room': {
            'id_str': 'fixture-room',
            'status': 2,
            'title': 'fixture',
            'cover': {
              'url_list': ['https://image.test/cover'],
            },
            'owner': {
              'nickname': 'fixture',
              'avatar_thumb': {
                'url_list': ['https://image.test/avatar'],
              },
            },
            'stream_url': {
              'flv_pull_url': {'origin': 'https://cdn.test/source.flv'},
            },
          },
        },
      },
    };
    final html = '${jsonEncode({'state': state}).replaceAll('"', r'\"')}${r']\n'}';
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            if (options.path.contains('/webcast/room/web/enter/')) {
              handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError));
              return;
            }
            handler.resolve(
              Response(
                requestOptions: options,
                data: options.method == 'HEAD' ? '' : html,
                headers: Headers.fromMap({
                  'set-cookie': ['ttwid=page-visitor; Path=/', '__ac_nonce=nonce; Path=/'],
                }),
              ),
            );
          },
        ),
      );
    HttpClient.instance.dio = dio;
    try {
      final detail = await DouyinSite().getRoomDetailByWebRid('1234');
      final head = requests.singleWhere((request) => request.method == 'HEAD');
      final page = requests.last;
      String cookieOf(RequestOptions request) =>
          request.headers.entries.singleWhere((entry) => entry.key.toLowerCase() == 'cookie').value.toString();

      expect(cookieOf(head), 'sessionid=account; ttwid=account-visitor');
      expect(cookieOf(page), 'sessionid=account; ttwid=account-visitor; __ac_nonce=nonce');
      expect(detail.status, isTrue);
      expect(DouyinSite.parseStreamQualities(detail.data).single.selectionId, 'origin');
      expect(DouyinSite.cookie, isEmpty);
    } finally {
      HttpClient.instance.dio = previous;
      dio.close(force: true);
    }
  });
}
