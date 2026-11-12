import 'dart:async';
import 'dart:io' show Directory;

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
  // ignore: must_call_super -- fixture avoids unrelated services.
  void onInit() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late CookieSettingsController cookies;
  late Dio previous;
  late Dio fixture;
  late List<RequestOptions> requests;
  late Completer<void> requestStarted;
  Completer<void>? responseGate;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('douyin-request-headers');
    Hive.init(temp.path);
    await HivePrefUtil.init();
    cookies = Get.put(CookieSettingsController());
    Get.put<SettingsService>(_Settings());
    DouyinSite.cookie = '';
    requests = [];
    requestStarted = Completer<void>();
    responseGate = null;
    previous = HttpClient.instance.dio;
    fixture = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requests.add(options);
            if (!requestStarted.isCompleted) requestStarted.complete();
            if (responseGate != null) await responseGate!.future;
            handler.resolve(
              Response(
                requestOptions: options,
                data: 'ok',
                headers: Headers.fromMap({
                  'set-cookie': ['ttwid=visitor; Path=/', 'UIFID_TEMP=visitor-id; Path=/'],
                }),
              ),
            );
          },
        ),
      );
    HttpClient.instance.dio = fixture;
  });

  tearDown(() async {
    HttpClient.instance.dio = previous;
    fixture.close(force: true);
    DouyinSite.cookie = '';
    Get.reset();
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('logout without a visitor cache bootstraps anonymously and never retains the account', () async {
    final site = DouyinSite();
    cookies.setAccountCookie('douyin', 'sessionid=account');

    expect((await site.getRequestHeaders())['cookie'], 'sessionid=account');
    expect(DouyinSite.cookie, isEmpty);
    expect(requests, isEmpty);

    cookies.setAccountCookie('douyin', '');
    final visitorHeaders = await site.getRequestHeaders();
    expect(visitorHeaders['cookie'], 'ttwid=visitor; UIFID_TEMP=visitor-id');
    expect(DouyinSite.cookie, visitorHeaders['cookie']);
    expect(requests, hasLength(1));
    expect(requests.single.uri.host, 'live.douyin.com');
    expect(requests.single.headers.keys.any((key) => key.toLowerCase() == 'cookie'), isFalse);
    expect(site.headers.keys.any((key) => key.toLowerCase() == 'cookie'), isFalse);

    expect((await DouyinSite().getRequestHeaders())['cookie'], visitorHeaders['cookie']);
    expect(requests, hasLength(1));
  });

  test('concurrent anonymous header requests share one bootstrap and reuse its visitor cookie', () async {
    responseGate = Completer<void>();
    final pending = List.generate(8, (_) => DouyinSite().getRequestHeaders());
    await requestStarted.future;
    responseGate!.complete();
    final results = await Future.wait(pending);

    expect(requests, hasLength(1));
    for (final headers in results) {
      expect(headers['cookie'], 'ttwid=visitor; UIFID_TEMP=visitor-id');
    }
    expect((await DouyinSite().getRequestHeaders())['cookie'], 'ttwid=visitor; UIFID_TEMP=visitor-id');
    expect(requests, hasLength(1));
  });
}
