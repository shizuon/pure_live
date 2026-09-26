import 'package:pure_live/core/site/douyu/douyu_cookie.dart';

bool isDouyuLoginUrl(Uri? uri) =>
    uri != null && uri.scheme == 'https' && (uri.host == 'douyu.com' || uri.host.endsWith('.douyu.com'));

/// Session-cookie presence is not a server-side authentication/entitlement
/// check. Never label it as proof that source quality is unlocked.
bool hasDouyuAccountSession(String cookie) {
  final fields = <String, String>{};
  for (final part in normalizeDouyuCookie(cookie).split('; ')) {
    final split = part.indexOf('=');
    if (split > 0) fields[part.substring(0, split)] = part.substring(split + 1);
  }
  final uid = int.tryParse(fields['acf_uid'] ?? '') ?? 0;
  final auth = fields['acf_auth'] ?? '';
  return uid > 0 && auth.isNotEmpty && auth != 'deleted' && auth != 'null';
}

/// Only one cookie-store read at a time. Closing the login route invalidates
/// late results so they cannot overwrite a newer account or undo a logout.
class DouyuLoginSession {
  DouyuLoginSession({required this.readCookies, required this.save});

  final Future<String> Function() readCookies;
  final void Function(String) save;
  bool _disposed = false;
  bool _reading = false;
  bool _completed = false;

  Future<bool> check() async {
    if (_disposed || _reading || _completed) return false;
    _reading = true;
    try {
      final cookie = await readCookies();
      if (_disposed || _completed || !hasDouyuAccountSession(cookie)) return false;
      save(normalizeDouyuCookie(cookie));
      _completed = true;
      return true;
    } finally {
      _reading = false;
    }
  }

  void dispose() => _disposed = true;
}
