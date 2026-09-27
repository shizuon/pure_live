import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/bilibili/bilibili_site.dart';

class _Site extends BiliBiliSite {
  String session = 'SESSDATA=fixture; DedeUserID=42; buvid3=device';
  final keyRefreshes = <bool>[];
  @override
  String get cookie => session;
  @override
  int get userId => 999;
  @override
  Future<(String, String)> getWbiKeys({bool forceRefresh = false}) async {
    keyRefreshes.add(forceRefresh);
    return ('abcdefghijklmnopqrstuvwxyz012345', '012345abcdefghijklmnopqrstuvwxyz');
  }
}

void main() {
  late Dio old;
  late Dio fixture;
  late _Site site;
  late bool loggedIn;
  late int navUid;
  late int playCode;
  late int navCalls;
  late List<String> requestCookies;
  late void Function()? afterDiscovery;
  setUp(() {
    old = HttpClient.instance.dio;
    site = _Site();
    loggedIn = true;
    navUid = 42;
    playCode = 0;
    navCalls = 0;
    requestCookies = [];
    afterDiscovery = null;
    BiliBiliSite.buvid3 = '';
    BiliBiliSite.buvid4 = '';
    fixture = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestCookies.add(options.headers['cookie']?.toString() ?? '');
            final Map<String, dynamic> data;
            if (options.path.endsWith('/nav')) {
              navCalls++;
              data = {
                'code': loggedIn ? 0 : -101,
                'data': {'isLogin': loggedIn, 'mid': navUid},
              };
            } else if (options.path.endsWith('/spi')) {
              data = {
                'code': 0,
                'data': {'b_3': 'fresh-device', 'b_4': 'fresh-four'},
              };
            } else {
              expect(options.path, endsWith('/getDanmuInfo'));
              afterDiscovery?.call();
              data = {
                'code': playCode,
                'data': {
                  'token': 'fixture-token',
                  'host_list': [
                    {'host': 'test.chat.bilibili.com', 'wss_port': 443},
                  ],
                },
              };
            }
            handler.resolve(Response(requestOptions: options, data: data));
          },
        ),
      );
    HttpClient.instance.dio = fixture;
  });
  tearDown(() {
    HttpClient.instance.dio = old;
    fixture.close(force: true);
  });
  test('reconnect forces fresh WBI keys even with one discovery attempt', () async {
    final args = await site.getDanmakuArgs(123);
    await args.refresh!();
    expect(site.keyRefreshes, [false, true]);
  });
  test('logged-in discovery verifies server identity even when cookie contains UID', () async {
    final args = await site.getDanmakuArgs(123);
    expect(navCalls, 1);
    expect(args.uid, 42);
    expect(args.buvid, 'device');
    expect(requestCookies, everyElement(contains('SESSDATA=fixture')));
  });
  test('expired session is not accepted simply because DedeUserID exists', () async {
    loggedIn = false;
    await expectLater(site.getDanmakuArgs(123), throwsA(predicate((e) => e.toString().contains('登录'))));
    expect(site.keyRefreshes, isEmpty);
  });
  test('mixed identity cannot send a token for one user with another auth UID', () async {
    navUid = 77;
    await expectLater(site.getDanmakuArgs(123), throwsA(predicate((e) => e.toString().contains('登录'))));
  });
  test('empty buvid is repaired while an end-of-header valid buvid is preserved', () async {
    site.session = 'SESSDATA=fixture; DedeUserID=42; buvid3=';
    final args = await site.getDanmakuArgs(123);
    expect(args.buvid, 'fresh-device');
    expect(args.headers['cookie'], contains('buvid3=fresh-device'));
    expect(args.headers['cookie'], isNot(contains('buvid3=;')));
    site.session = 'SESSDATA=other; DedeUserID=42; buvid3=last';
    expect((await site.getDanmakuArgs(123)).buvid, 'last');
  });
  test('account switch during discovery fences the old token and risk-control errors remain retryable', () async {
    afterDiscovery = () => site.session = 'SESSDATA=new; DedeUserID=77; buvid3=new-device';
    await expectLater(site.getDanmakuArgs(123), throwsA(isA<StateError>()));
    afterDiscovery = null;
    site.session = 'SESSDATA=fixture; DedeUserID=42; buvid3=device';
    playCode = -352;
    await expectLater(
      site.getDanmakuArgs(123),
      throwsA(predicate((e) => e.toString().contains('code=-352') && !e.toString().contains('SESSDATA'))),
    );
  });
  test('anonymous discovery does not validate an unrelated persisted account', () async {
    site.session = 'buvid3=anonymous';
    final args = await site.getDanmakuArgs(123);
    expect(navCalls, 0);
    expect(args.uid, 0);
    expect(args.buvid, 'anonymous');
  });
}
