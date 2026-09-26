import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'platform_login_profile.dart';

class PlatformWebSession {
  const PlatformWebSession(this.profile);
  final PlatformLoginProfile profile;

  Future<String> read() async {
    final fields = <String, String>{};
    for (final url in profile.cookieUrls) {
      for (final cookie in await CookieManager.instance().getCookies(url: WebUri(url))) {
        // Native implementations differ on expiry units; the cookie store
        // owns expiry. Explicitly filter domains because older plugins use a
        // suffix match rather than an exact domain boundary.
        if (cookie.domain != null && !profile.ownsDomain(cookie.domain)) continue;
        if (cookie.path != null && !Uri.parse(url).path.startsWith(cookie.path!)) continue;
        fields.putIfAbsent(cookie.name, () => cookie.value);
      }
    }
    return fields.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<void> clear() async {
    final manager = CookieManager.instance();
    final failures = <String>[];
    for (final url in {...profile.cookieUrls, profile.loginUrl}) {
      try {
        for (final cookie in await manager.getCookies(url: WebUri(url))) {
          if (cookie.domain != null && !profile.ownsDomain(cookie.domain)) continue;
          if (!await manager.deleteCookie(
            url: WebUri(url),
            name: cookie.name,
            domain: cookie.domain,
            path: cookie.path ?? '/',
          )) {
            failures.add('delete');
          }
        }
      } catch (_) {
        failures.add('store');
      }
    }
    if (failures.isNotEmpty) throw StateError('Platform web session cleanup incomplete');
  }
}
