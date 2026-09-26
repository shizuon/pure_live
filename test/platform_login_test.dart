import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/services/settings/cookie_settings_controller.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/douyin/douyin_site.dart';
import 'package:pure_live/core/site/twitch/twitch_site.dart';
import 'package:pure_live/modules/account/platform_login_profile.dart';
import 'package:pure_live/modules/account/platform_web_login_page.dart';
import 'package:pure_live/modules/account/platform_account_page.dart';

class _Settings extends SettingsService {
  @override
  // ignore: must_call_super -- no services/network in account fixture.
  void onInit() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late CookieSettingsController cookies;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('platform-login');
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

  test('site boundaries reject lookalikes, non-HTTPS and shared SSO cookie capture', () {
    for (final p in PlatformLoginProfile.profiles) {
      expect(p.allows(Uri.parse(p.loginUrl)), isTrue);
      expect(p.allows(Uri.parse('https://${Uri.parse(p.loginUrl).host}.attacker.test')), isFalse);
      expect(p.allows(Uri.parse(p.loginUrl.replaceFirst('https:', 'http:'))), isFalse);
      expect(p.ownsDomain('.com'), isFalse);
      expect(p.hasSession('visitor=1; did=x; ttwid=anonymous'), isFalse);
    }
    expect(PlatformLoginProfile.of('huya').ownsDomain('.udb.com'), isFalse);
    expect(PlatformLoginProfile.of('yy').ownsDomain('.udb.com'), isFalse);
    expect(PlatformLoginProfile.of('douyin').hasSession('sessionid=token'), isTrue);
    expect(PlatformLoginProfile.of('douyu').ownsDomain('passport.douyu.com'), isTrue);
    expect(PlatformLoginProfile.of('douyu').ownsDomain('fake-douyu.com'), isFalse);
  });
  test('capture cannot save after close or twice; errors permit retry', () async {
    final pending = Completer<String>();
    final saved = <String>[];
    final c = PlatformLoginCapture(read: () => pending.future, accept: (_) => true, save: saved.add);
    final future = c.check();
    expect(await c.check(), isFalse);
    c.close();
    pending.complete('auth=fixture');
    expect(await future, isFalse);
    expect(saved, isEmpty);
    var fail = true;
    final retry = PlatformLoginCapture(
      read: () async {
        if (fail) throw StateError('fixture');
        return 'auth=fixture';
      },
      accept: (_) => true,
      save: saved.add,
    );
    await expectLater(retry.check(), throwsStateError);
    fail = false;
    expect(await retry.check(), isTrue);
    expect(await retry.check(), isFalse);
    expect(saved, hasLength(1));
  });
  test('account sessions persist locally, never exported, empty backup does not log out', () async {
    for (final p in PlatformLoginProfile.profiles) {
      cookies.setAccountCookie(p.id, 'Cookie: token=${p.id}; value=a==\r\n');
    }
    await Hive.box('app_settings').flush();
    final restored = CookieSettingsController();
    expect(restored.huyaCookie.value, contains('token=huya'));
    expect(cookies.toJson(), isEmpty);
    cookies.fromJson({});
    expect(cookies.huyaCookie.value, contains('token=huya'));
    cookies.clearAllCookies();
    for (final p in PlatformLoginProfile.profiles) {
      expect(cookies.accountCookie(p.id).value, isEmpty);
    }
  });
  test('Douyin account takes priority over cached anonymous and logout restores visitor', () async {
    DouyinSite.cookie = 'ttwid=visitor';
    cookies.setAccountCookie('douyin', 'sessionid=account');
    final site = DouyinSite();
    expect((await site.getRequestHeaders())['cookie'], 'sessionid=account');
    expect(DouyinSite.cookie, 'ttwid=visitor');
    cookies.setAccountCookie('douyin', '');
    expect((await site.getRequestHeaders())['cookie'], 'ttwid=visitor');
  });
  test('login finishing during Douyin anonymous bootstrap wins the late response', () async {
    final previous = HttpClient.instance.dio;
    final pending = Completer<void>();
    final started = Completer<void>();
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            started.complete();
            await pending.future;
            handler.resolve(
              Response(
                requestOptions: options,
                data: 'ok',
                headers: Headers.fromMap({
                  'set-cookie': ['ttwid=visitor; Path=/'],
                }),
              ),
            );
          },
        ),
      );
    HttpClient.instance.dio = dio;
    try {
      final future = DouyinSite().getRequestHeaders();
      await started.future;
      cookies.setAccountCookie('douyin', 'sessionid=account');
      pending.complete();
      expect((await future)['cookie'], 'sessionid=account');
      expect(DouyinSite.cookie, isNot(contains('sessionid')));
    } finally {
      HttpClient.instance.dio = previous;
      dio.close(force: true);
    }
  });
  test('Twitch auth reaches GraphQL and is removed on logout', () {
    final site = TwitchSite();
    cookies.setAccountCookie('twitch', 'auth-token=fixture; login=test');
    site.getRequestHeaders();
    expect(site.headers['Authorization'], 'OAuth fixture');
    cookies.setAccountCookie('twitch', '');
    site.getRequestHeaders();
    expect(site.headers, isNot(contains('Cookie')));
    expect(site.headers, isNot(contains('Authorization')));
  });
  testWidgets('platform account has primary web login or honest Linux fallback; manual input collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PlatformAccountPage(platform: 'huya')));
    expect(find.byKey(const ValueKey('platform-web-login')), Platform.isLinux ? findsNothing : findsOneWidget);
    expect(find.byKey(const ValueKey('platform-cookie-input')), findsNothing);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('platform-cookie-input'))).obscureText, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
