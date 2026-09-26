import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';
import 'package:pure_live/common/services/settings/bilibili_account_service.dart';
import 'package:pure_live/core/site/douyu/douyu_cookie.dart';

class CookieSettingsController extends GetxController {
  final RxString bilibiliCookie = hiveString('bilibiliCookie', '');
  final RxInt bilibiliUid = hiveInt('bilibiliUid', 0);
  final RxString huyaCookie = hiveString('huyaCookie', '');
  final RxString douyuCookie = hiveString('douyuCookie', '');

  void setDouyuCookie(String value) => douyuCookie.value = normalizeDouyuCookie(value);
  final RxString douyinCookie = hiveString('douyinCookie', '');
  final RxString kuaishouCookie = hiveString('kuaishouCookie', '');
  final RxString twitchCookie = hiveString('twitchCookie', '');
  final RxString soopCookie = hiveString('soopCookie', '');
  final RxString yyCookie = hiveString('yyCookie', '');

  RxString accountCookie(String platform) => switch (platform) {
    'bilibili' => bilibiliCookie,
    'huya' => huyaCookie,
    'douyu' => douyuCookie,
    'douyin' => douyinCookie,
    'kuaishou' => kuaishouCookie,
    'twitch' => twitchCookie,
    'soop' => soopCookie,
    'yy' => yyCookie,
    _ => throw ArgumentError.value(platform, 'platform'),
  };

  void setAccountCookie(String platform, String value) => accountCookie(platform).value = normalizeDouyuCookie(value);
  void clearAllCookies() {
    bilibiliCookie.v = '';
    huyaCookie.v = '';
    douyuCookie.v = '';
    douyinCookie.v = '';
    kuaishouCookie.v = '';
    twitchCookie.v = '';
    soopCookie.v = '';
    yyCookie.v = '';
    bilibiliUid.v = 0;
  }

  Map<String, dynamic> toJson() {
    // Web-login sessions belong to this device, not settings backups. Hive
    // persists them separately. Legacy explicit imports remain supported.
    return {};
  }

  void fromJson(Map<String, dynamic> json) {
    for (final platform in ['bilibili', 'huya', 'douyu', 'douyin', 'kuaishou', 'twitch', 'soop', 'yy']) {
      final key = '${platform}Cookie';
      if (json.containsKey(key)) setAccountCookie(platform, json[key] is String ? json[key] as String : '');
    }
    if (json.containsKey('bilibiliUid')) bilibiliUid.v = (json['bilibiliUid'] as num?)?.toInt() ?? 0;
    if (json.containsKey('bilibiliCookie') && Get.isRegistered<BiliBiliAccountService>()) {
      BiliBiliAccountService.instance.loadUserInfo();
    }
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final cookie = rootConfig?['cookie'] as Map<String, dynamic>? ?? {};
    return {
      'bilibiliCookie': cookie['bilibiliCookie'] ?? '',
      'huyaCookie': cookie['huyaCookie'] ?? '',
      'douyuCookie': normalizeDouyuCookie(cookie['douyuCookie'] is String ? cookie['douyuCookie'] as String : ''),
      'douyinCookie': cookie['douyinCookie'] ?? '',
      'kuaishouCookie': cookie['kuaishouCookie'] ?? '',
      'bilibiliUid': cookie['bilibiliUid'] ?? 0,
      'twitchCookie': cookie['twitchCookie'] ?? '',
      'soopCookie': cookie['soopCookie'] ?? '',
      'yyCookie': cookie['yyCookie'] ?? '',
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final cookie = Map<String, dynamic>.from(rootConfig['cookie'] ?? {});
    updateFields.forEach((k, v) => cookie[k] = v);
    rootConfig['cookie'] = cookie;
    return rootConfig;
  }
}
