import 'dart:convert';
import 'dart:io' show Cookie;

import 'package:dio/dio.dart';

import 'douyu_cookie.dart';
import 'douyu_utils.dart';

enum DouyuRefreshFailure { missingCredential, loginRequired, accountMismatch, temporary }

class DouyuRefreshException implements Exception {
  const DouyuRefreshException(this.failure);
  final DouyuRefreshFailure failure;

  // Never expose a Dio request, redirect URL, response body or cookie value.
  @override
  String toString() => 'Douyu cookie refresh: ${failure.name}';
}

class DouyuRefreshCredential {
  const DouyuRefreshCredential({required this.ticket, required this.deviceId});
  final String ticket, deviceId;
}

class DouyuRefreshedCookie {
  const DouyuRefreshedCookie(this.origin, this.cookie);
  final Uri origin;
  final Cookie cookie;
}

class DouyuCookieRefreshResult {
  const DouyuCookieRefreshResult({required this.cookie, this.nativeCookies = const []});
  final String cookie;
  final List<DouyuRefreshedCookie> nativeCookies;
}

/// Isolated transport: shared API interceptors/jars must not log credentials or
/// mix this exchange with another account. Only the two demonstrated HTTPS
/// exchange endpoints can receive the passport ticket; normal APIs never do.
class DouyuCookieRefresher {
  DouyuCookieRefresher({Dio? client}) : _client = client ?? Dio() {
    _client.options.connectTimeout = const Duration(seconds: 10);
  }
  final Dio _client;

  static final safeAuthUrl = Uri.parse('https://passport.douyu.com/lapi/passport/iframe/safeAuth');
  static final probeUrl = Uri.parse('https://www.douyu.com/wgapi/livenc/liveweb/follow/top3');
  static const requiredFields = ['acf_uid', 'acf_auth', 'acf_stk', 'acf_ltkid', 'acf_username', 'acf_biz', 'acf_ct'];

  static bool allowsExchange(Uri url) =>
      url.scheme == 'https' &&
      (!url.hasPort || url.port == 443) &&
      url.userInfo.isEmpty &&
      !url.hasFragment &&
      ((url.host == 'passport.douyu.com' && url.path == '/lapi/passport/iframe/safeAuth') ||
          ((url.host == 'www.douyu.com' || url.host == 'douyu.com') && url.path == '/api/passport/login'));

  static bool _validCredential(String value) => value.isNotEmpty && !RegExp(r'[\x00-\x20\x7f;,]').hasMatch(value);

  Future<DouyuCookieRefreshResult> refresh({
    required String accountCookie,
    required DouyuRefreshCredential credential,
    required CancelToken cancelToken,
  }) async {
    try {
      return await _exchange(accountCookie, credential, cancelToken);
    } on DouyuRefreshException {
      rethrow;
    } catch (_) {
      throw const DouyuRefreshException(DouyuRefreshFailure.temporary);
    } finally {
      _client.close(force: true);
    }
  }

  Future<DouyuCookieRefreshResult> _exchange(
    String original,
    DouyuRefreshCredential credential,
    CancelToken cancelToken,
  ) async {
    if (!_validCredential(credential.ticket) || !_validCredential(credential.deviceId)) {
      throw const DouyuRefreshException(DouyuRefreshFailure.missingCredential);
    }
    final previous = douyuCookieFields(original)..remove('LTP0');
    final expectedUid = int.tryParse(previous['acf_uid'] ?? '');
    if (expectedUid == null || expectedUid <= 0) {
      throw const DouyuRefreshException(DouyuRefreshFailure.loginRequired);
    }
    final passport = {'LTP0': credential.ticket, 'dy_did': credential.deviceId};
    final fresh = <String, String>{};
    final native = <String, DouyuRefreshedCookie>{};
    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    var url = safeAuthUrl.replace(queryParameters: {'client_id': '1', 't': stamp, '_': stamp, 'callback': 'cb'});
    var completed = false;
    for (var hop = 0; hop < 4; hop++) {
      if (!allowsExchange(url)) throw const DouyuRefreshException(DouyuRefreshFailure.temporary);
      final isMainSite = url.host != 'passport.douyu.com';
      final requestCookies = {...passport, if (isMainSite) ...fresh}..['dy_did'] = passport['dy_did']!;
      final response = await _get(url, _header(requestCookies), cancelToken);
      final status = response.statusCode ?? 0;
      if (status != 200 && (status < 300 || status >= 400)) {
        throw const DouyuRefreshException(DouyuRefreshFailure.temporary);
      }
      for (final header in response.headers['set-cookie'] ?? const <String>[]) {
        final cookie = Cookie.fromSetCookieValue(header);
        final domain = cookie.domain?.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
        if (domain != null && domain != 'douyu.com' && domain != url.host) {
          throw const DouyuRefreshException(DouyuRefreshFailure.temporary);
        }
        if (cookie.path != null && cookie.path != '/') continue;
        final name = cookie.name;
        final target = isMainSite && (name.startsWith('acf_') || name == 'dy_did' || name == 'dy_auth')
            ? fresh
            : !isMainSite && (name == 'LTP0' || name == 'dy_did')
            ? passport
            : null;
        if (target == null) continue;
        final expired = cookie.maxAge != null ? cookie.maxAge! <= 0 : cookie.expires?.isBefore(DateTime.now()) == true;
        if (expired || cookie.value.isEmpty || cookie.value == 'deleted') {
          target.remove(name);
        } else {
          if (!_validCredential(cookie.value)) throw const DouyuRefreshException(DouyuRefreshFailure.temporary);
          target[name] = cookie.value;
        }
        native['${domain ?? url.host}:${cookie.path ?? '/'}:$name'] = DouyuRefreshedCookie(url, cookie);
      }
      if (status >= 300 && status < 400) {
        final location = response.headers.value('location');
        if (location == null) throw const DouyuRefreshException(DouyuRefreshFailure.temporary);
        url = url.resolve(location);
        continue;
      }
      completed = true;
      break;
    }
    if (!completed) throw const DouyuRefreshException(DouyuRefreshFailure.temporary);
    if (requiredFields.any((key) => fresh[key]?.isNotEmpty != true) || passport['LTP0']?.isNotEmpty != true) {
      throw const DouyuRefreshException(DouyuRefreshFailure.loginRequired);
    }
    if (int.tryParse(fresh['acf_uid']!) != expectedUid) {
      throw const DouyuRefreshException(DouyuRefreshFailure.accountMismatch);
    }

    // Keep the existing main-site DID stable. A passport DID belongs to that
    // login session and must not replace the main-site playback device ID.
    const deviceKeys = ['dy_did', 'acf_did', 'acf_devid'];
    final merged = {...previous, ...fresh}..remove('LTP0');
    for (final key in deviceKeys) {
      if (previous[key]?.isNotEmpty == true) merged[key] = previous[key]!;
    }
    final cookie = _header(merged);
    final probe = await _get(probeUrl, cookie, cancelToken);
    if (probe.statusCode != 200) throw const DouyuRefreshException(DouyuRefreshFailure.temporary);
    final dynamic body = jsonDecode(probe.data ?? '');
    if (body is! Map || body['error'] is! num) {
      throw const DouyuRefreshException(DouyuRefreshFailure.temporary);
    }
    if (body['error'] != 0) throw const DouyuRefreshException(DouyuRefreshFailure.loginRequired);

    // Persist only the verified exchange. Device cookies retained above must
    // also remain stable in the native store; never write a conflicting DID.
    return DouyuCookieRefreshResult(
      cookie: cookie,
      nativeCookies: native.values
          .where((item) {
            final isMain = item.origin.host != 'passport.douyu.com';
            return !isMain || !deviceKeys.contains(item.cookie.name) || previous[item.cookie.name]?.isNotEmpty != true;
          })
          .toList(growable: false),
    );
  }

  Future<Response<String>> _get(Uri uri, String cookie, CancelToken cancelToken) => _client.getUri<String>(
    uri,
    cancelToken: cancelToken,
    options: Options(
      followRedirects: false,
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: {
        'cookie': cookie,
        'user-agent': DouyuUtils.userAgent,
        'referer': 'https://www.douyu.com/',
        'origin': 'https://www.douyu.com',
      },
    ),
  );

  static String _header(Map<String, String> fields) => fields.entries.map((e) => '${e.key}=${e.value}').join('; ');
}
