import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/services/settings/cookie_settings_controller.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';
import 'package:pure_live/core/site/douyu/douyu_utils.dart';
import 'package:pure_live/player/core/playback_header_resolver.dart';
import 'package:pure_live/recorder/services/ffmpeg_header_factory.dart';
import 'package:pure_live/modules/account/douyu/douyu_cookie_page.dart';

class _Settings extends SettingsService {
  @override
  // ignore: must_call_super -- isolated account fixture without background services.
  void onInit() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late CookieSettingsController cookies;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('douyu-account-test');
    Hive.init(directory.path);
    await HivePrefUtil.init();
    cookies = Get.put(CookieSettingsController());
    Get.put<SettingsService>(_Settings());
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  test('persisted session reaches signing, A/B and recording; clearing returns anonymous', () async {
    expect(cookies.douyuCookie.value, isEmpty);
    cookies.setDouyuCookie('Cookie: acf_uid=123; acf_auth=fixture; dy_did=old\r\n');
    await Hive.box('app_settings').flush();
    expect(CookieSettingsController().douyuCookie.value, cookies.douyuCookie.value);
    expect(cookies.toJson(), isNot(contains('douyuCookie')));
    final media = await PlaybackHeaderResolver.resolve(platform: 'douyu', roomId: '123');
    expect(media['cookie'], DouyuUtils.requestHeaders('123')['cookie']);
    expect(media['cookie'], contains('acf_auth=fixture'));
    expect(media['cookie'], isNot(contains('dy_did=old')));
    expect(await FFmpegHeaderFactory.build(platform: 'douyu', roomId: '123'), media);
    expect(BackupController.redactSensitiveData({'cookie': cookies.toJson()}), isNot(contains('cookie')));
    cookies.setDouyuCookie('');
    expect(DouyuUtils.cookieHeader(), isNot(contains('acf_auth')));
    expect(CookieSettingsController.extractConfig({})['douyuCookie'], '');
  });
  testWidgets('web login is primary and manual Cookie is collapsed advanced UI', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DouyuCookiePage()));
    expect(find.byKey(const ValueKey('douyu-web-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('douyu-cookie-input')), findsNothing);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('douyu-cookie-input')), findsOneWidget);
    final text = tester.widget<TextField>(find.byKey(const ValueKey('douyu-cookie-input')));
    expect(text.obscureText, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
