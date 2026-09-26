import 'package:pure_live/core/site/douyu/douyu_cookie.dart';

/// Public first-party pages only. Cookie presence is a session candidate,
/// never proof of entitlement, successful server authentication or source FPS.
class PlatformLoginProfile {
  const PlatformLoginProfile({
    required this.id,
    required this.name,
    required this.loginUrl,
    required this.cookieUrls,
    required this.domains,
    this.sessionKeys = const [],
  });
  final String id;
  final String name;
  final String loginUrl;
  final List<String> cookieUrls;
  final List<String> domains;
  final List<String> sessionKeys;

  bool allows(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      domains.any((domain) => uri.host == domain || uri.host.endsWith('.$domain'));

  bool ownsDomain(String? domain) {
    final value = (domain ?? '').replaceFirst(RegExp(r'^\.'), '').toLowerCase();
    // Navigation can include a shared SSO provider (e.g. udb.com). Never
    // capture or clear that provider's cross-platform cookies.
    return value.isNotEmpty && domains.where((d) => d != 'udb.com').any((d) => value == d || value.endsWith('.$d'));
  }

  bool hasSession(String cookie) {
    final fields = <String, String>{};
    for (final item in normalizeDouyuCookie(cookie).split('; ')) {
      final split = item.indexOf('=');
      if (split > 0) fields[item.substring(0, split)] = item.substring(split + 1);
    }
    if (id == 'douyu') {
      if ((int.tryParse(fields['acf_uid'] ?? '') ?? 0) <= 0) return false;
    }
    return sessionKeys.any((key) {
      final value = fields[key] ?? '';
      return value.isNotEmpty && value != 'deleted' && value != 'null' && value != '0';
    });
  }

  static const profiles = [
    PlatformLoginProfile(
      id: 'huya',
      name: '虎牙',
      loginUrl: 'https://www.huya.com/',
      cookieUrls: ['https://www.huya.com/'],
      domains: ['huya.com', 'udb.com'],
      sessionKeys: ['udb_l', 'udb_passdata'],
    ),
    PlatformLoginProfile(
      id: 'douyu',
      name: '斗鱼',
      loginUrl: 'https://passport.douyu.com/member/login',
      cookieUrls: ['https://www.douyu.com/'],
      domains: ['douyu.com'],
      sessionKeys: ['acf_auth'],
    ),
    PlatformLoginProfile(
      id: 'douyin',
      name: '抖音',
      loginUrl: 'https://live.douyin.com/',
      cookieUrls: ['https://live.douyin.com/', 'https://www.douyin.com/'],
      domains: ['douyin.com'],
      sessionKeys: ['sessionid', 'sessionid_ss'],
    ),
    PlatformLoginProfile(
      id: 'kuaishou',
      name: '快手',
      loginUrl: 'https://live.kuaishou.com/',
      cookieUrls: ['https://live.kuaishou.com/'],
      domains: ['kuaishou.com'],
      sessionKeys: ['kuaishou.live.web_st'],
    ),
    PlatformLoginProfile(
      id: 'twitch',
      name: 'Twitch',
      loginUrl: 'https://www.twitch.tv/login',
      cookieUrls: ['https://www.twitch.tv/'],
      domains: ['twitch.tv'],
      sessionKeys: ['auth-token'],
    ),
    PlatformLoginProfile(
      id: 'yy',
      name: 'YY',
      loginUrl: 'https://www.yy.com/',
      cookieUrls: ['https://www.yy.com/'],
      domains: ['yy.com', 'udb.com'],
      sessionKeys: ['udb_l', 'udb_passdata'],
    ),
    PlatformLoginProfile(
      id: 'soop',
      name: 'SOOP',
      loginUrl: 'https://login.sooplive.co.kr/afreeca/login.php',
      cookieUrls: ['https://live.sooplive.co.kr/', 'https://live.sooplive.com/'],
      domains: ['sooplive.co.kr', 'sooplive.com', 'afreecatv.com'],
      sessionKeys: ['PdboxBbs', 'AuthTicket'],
    ),
    PlatformLoginProfile(
      id: 'bilibili',
      name: '哔哩哔哩',
      loginUrl: 'https://passport.bilibili.com/login',
      cookieUrls: ['https://live.bilibili.com/', 'https://www.bilibili.com/'],
      domains: ['bilibili.com'],
      sessionKeys: ['SESSDATA'],
    ),
  ];
  static PlatformLoginProfile of(String id) => profiles.firstWhere((p) => p.id == id);
}
