import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/modules/account/platform_web_session.dart';
import 'package:pure_live/modules/account/platform_login_profile.dart';
import 'package:pure_live/common/models/bilibili_user_info_page.dart';

class BiliBiliAccountService extends GetxController {
  static BiliBiliAccountService get instance => Get.find<BiliBiliAccountService>();

  final RxBool logined = false.obs;
  final RxString name = ''.obs;

  String get currentCookie => SettingsService.to.cookieManager.bilibiliCookie.v;
  Timer? _initialTimer;
  Worker? _cookieWorker;
  bool _closed = false;
  int _generation = 0;

  @override
  void onInit() {
    super.onInit();
    _initialTimer = Timer(const Duration(seconds: 1), _initAfterDelay);
  }

  void _initAfterDelay() {
    if (_closed) return;
    _cookieWorker = ever<String>(SettingsService.to.cookieManager.bilibiliCookie, (val) {
      _generation++;
      logined.value = false;
      val.isEmpty ? _clearLocalAccountState() : loadUserInfo();
    });

    if (currentCookie.isNotEmpty) {
      loadUserInfo();
    }
  }

  Future<void> loadUserInfo() async {
    if (currentCookie.isEmpty) return;
    final generation = ++_generation;
    final cookie = currentCookie;

    try {
      final result = await HttpClient.instance.getJson(
        "https://api.bilibili.com/x/member/web/account",
        header: {"Cookie": cookie},
      );
      if (_closed || generation != _generation || currentCookie != cookie) return;
      if (result == null || result["code"] != 0) {
        ToastUtil.show(i18n("bilibili_login_expired"));
        clearLocalSession();
        return;
      }

      final info = BiliBiliUserInfoModel.fromJson(result["data"]);
      logined.value = true;
      name.value = info.uname ?? i18n("not_logged_in");
      SettingsService.to.cookieManager.bilibiliUid.value = info.mid ?? 0;
    } catch (_) {
      if (!_closed && generation == _generation) ToastUtil.show(i18n("bilibili_user_info_failed"));
    }
  }

  void setCookie(String cookie) {
    SettingsService.to.cookieManager.bilibiliCookie.value = cookie;
  }

  void _clearLocalAccountState() {
    logined.value = false;
    name.value = i18n("not_logged_in");
    SettingsService.to.cookieManager.bilibiliUid.value = 0;
  }

  void clearLocalSession() {
    _generation++;
    SettingsService.to.cookieManager.bilibiliCookie.value = "";
    _clearLocalAccountState();
  }

  Future<void> logout() async {
    clearLocalSession();
    if (PlatformUtils.isLinux) return;
    try {
      await PlatformWebSession(PlatformLoginProfile.of('bilibili')).clear();
    } catch (_) {
      ToastUtil.show(i18n('platform_logout_web_failed'));
    }
  }

  @override
  void onClose() {
    _closed = true;
    _generation++;
    _initialTimer?.cancel();
    _cookieWorker?.dispose();
    super.onClose();
  }
}
