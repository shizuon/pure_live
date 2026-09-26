import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/services/settings/cookie_settings_controller.dart';
import 'package:pure_live/common/services/settings/bilibili_account_service.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/modules/account/bilibili/qr_login_controller.dart';

class _Settings extends SettingsService {
  @override
  // ignore: must_call_super -- fixture avoids unrelated services.
  void onInit() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Dio previous;
  late CookieSettingsController cookies;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bili-lifecycle');
    Hive.init(temp.path);
    await HivePrefUtil.init();
    cookies = Get.put(CookieSettingsController());
    Get.put<SettingsService>(_Settings());
    previous = HttpClient.instance.dio;
  });
  tearDown(() async {
    if (!identical(HttpClient.instance.dio, previous)) HttpClient.instance.dio.close(force: true);
    HttpClient.instance.dio = previous;
    Get.reset();
    await Hive.close();
    await temp.delete(recursive: true);
  });
  test('late account response cannot restore profile after logout', () async {
    final pending = Completer<void>();
    final started = Completer<void>();
    HttpClient.instance.dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) async {
            started.complete();
            await pending.future;
            h.resolve(
              Response(
                requestOptions: o,
                data: {
                  'code': 0,
                  'data': {'mid': 42, 'uname': 'old'},
                },
              ),
            );
          },
        ),
      );
    final service = BiliBiliAccountService();
    cookies.bilibiliCookie.value = 'SESSDATA=old';
    cookies.huyaCookie.value = 'udb_l=other-platform';
    final request = service.loadUserInfo();
    await started.future;
    service.clearLocalSession();
    pending.complete();
    await request;
    expect(service.logined.value, isFalse);
    expect(cookies.bilibiliUid.value, 0);
    expect(cookies.bilibiliCookie.value, isEmpty);
    expect(cookies.huyaCookie.value, 'udb_l=other-platform');
    service.onClose();
  });
  test('QR generation response is ignored after closing route', () async {
    final pending = Completer<void>();
    final started = Completer<void>();
    HttpClient.instance.dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) async {
            started.complete();
            await pending.future;
            h.resolve(
              Response(
                requestOptions: o,
                data: {
                  'code': 0,
                  'data': {'qrcode_key': 'fixture', 'url': 'https://passport.bilibili.com/fixture'},
                },
              ),
            );
          },
        ),
      );
    final controller = BiliBiliQRLoginController();
    controller.loadQRCode();
    await started.future;
    controller.onClose();
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.qrcodeKey, isEmpty);
    expect(controller.timer?.isActive ?? false, isFalse);
  });
  test('overlapping QR polls are coalesced and close invalidates login cookies', () async {
    final pending = Completer<void>();
    final started = Completer<void>();
    var requests = 0;
    HttpClient.instance.dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) async {
            requests++;
            if (!started.isCompleted) started.complete();
            await pending.future;
            h.resolve(
              Response(
                requestOptions: o,
                data: {
                  'code': 0,
                  'data': {'code': 0},
                },
                headers: Headers.fromMap({
                  'set-cookie': ['SESSDATA=fixture; Path=/'],
                }),
              ),
            );
          },
        ),
      );
    final controller = BiliBiliQRLoginController()..qrcodeKey = 'key';
    controller.pollQRStatus();
    await started.future;
    controller.pollQRStatus();
    controller.onClose();
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    expect(cookies.bilibiliCookie.value, isEmpty);
  });
}
