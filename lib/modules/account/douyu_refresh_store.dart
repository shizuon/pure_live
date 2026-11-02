import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/core/site/douyu/douyu_cookie_refresh.dart';

/// Reads only this application's native Douyu session. Passport tickets never
/// enter Hive backups, the visible Cookie field, normal API or media headers.
class DouyuRefreshStore {
  static Future<DouyuRefreshCredential?> read() async {
    final url = DouyuCookieRefresher.safeAuthUrl;
    final cookies = await CookieManager.instance().getCookies(url: WebUri.uri(url));
    final fields = <String, String>{};
    for (final cookie in cookies) {
      final domain = cookie.domain?.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
      if (domain != null && domain != 'douyu.com' && domain != 'passport.douyu.com') continue;
      if (!url.path.startsWith(cookie.path ?? '/')) continue;
      if (cookie.name == 'LTP0' || cookie.name == 'dy_did') {
        // Prefer the passport host cookie over an inherited main-site value.
        if (!fields.containsKey(cookie.name) || domain == 'passport.douyu.com') fields[cookie.name] = cookie.value;
      }
    }
    if (fields['LTP0']?.isNotEmpty != true || fields['dy_did']?.isNotEmpty != true) return null;
    return DouyuRefreshCredential(ticket: fields['LTP0']!, deviceId: fields['dy_did']!);
  }

  static Future<void> write(List<DouyuRefreshedCookie> cookies, bool Function() current) async {
    final manager = CookieManager.instance();
    for (final item in cookies) {
      if (!current()) return;
      final c = item.cookie;
      final expiration = c.maxAge == null
          ? c.expires?.millisecondsSinceEpoch
          : DateTime.now().add(Duration(seconds: c.maxAge!)).millisecondsSinceEpoch;
      final saved = await manager.setCookie(
        url: WebUri.uri(item.origin.replace(query: '', fragment: '')),
        name: c.name,
        value: c.value,
        domain: c.domain,
        path: c.path ?? '/',
        expiresDate: expiration,
        isSecure: c.secure,
        isHttpOnly: c.httpOnly,
      );
      if (!saved) throw const DouyuRefreshException(DouyuRefreshFailure.temporary);
    }
  }
}
