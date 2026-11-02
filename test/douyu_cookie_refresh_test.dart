import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/douyu/douyu_cookie.dart';
import 'package:pure_live/core/site/douyu/douyu_cookie_refresh.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final ResponseBody Function(RequestOptions) reply;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body, Future<void>? cancelFuture) async {
    requests.add(options);
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

const _original = 'acf_uid=42; acf_auth=old; dy_did=web-device; acf_did=web-account-device';
const _credential = DouyuRefreshCredential(ticket: 'fixture-ticket', deviceId: 'passport-device');
const _bridge = 'https://www.douyu.com/api/passport/login?loginType=safeAuth&ticket=fixture';

List<String> _fresh({String uid = '42'}) => [
  'acf_uid=$uid; Domain=.douyu.com; Path=/; Max-Age=529200; Secure',
  for (final key in DouyuCookieRefresher.requiredFields.where((key) => key != 'acf_uid'))
    '$key=fresh; Domain=.douyu.com; Path=/; Max-Age=529200; Secure; HttpOnly',
  'dy_did=new-random-device; Domain=.douyu.com; Path=/',
];

_Adapter _adapter({
  String redirect = _bridge,
  List<String>? cookies,
  String probe = '{"error":0,"data":{}}',
  int status = 200,
}) => _Adapter((options) {
  expect(options.followRedirects, isFalse);
  if (options.uri.host == 'passport.douyu.com') {
    return ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': [redirect],
      },
    );
  }
  if (options.uri.path == '/api/passport/login') {
    return ResponseBody.fromString('cb({});', status, headers: {'set-cookie': cookies ?? _fresh()});
  }
  expect(options.uri, DouyuCookieRefresher.probeUrl);
  return ResponseBody.fromString(probe, 200);
});

Future<DouyuCookieRefreshResult> _refresh(
  _Adapter adapter, {
  String original = _original,
  DouyuRefreshCredential credential = _credential,
}) {
  final client = Dio()..httpClientAdapter = adapter;
  return DouyuCookieRefresher(client: client)
      .refresh(accountCookie: original, credential: credential, cancelToken: CancelToken());
}

Matcher _failure(DouyuRefreshFailure expected) =>
    throwsA(isA<DouyuRefreshException>().having((error) => error.failure, 'category', expected));

void main() {
  test('exchanges a passport ticket, verifies login and preserves main-site device IDs', () async {
    final adapter = _adapter();
    final result = await _refresh(adapter);
    final fields = douyuCookieFields(result.cookie);
    expect(fields['acf_auth'], 'fresh');
    expect(fields['dy_did'], 'web-device');
    expect(fields['acf_did'], 'web-account-device');
    expect(fields, isNot(contains('LTP0')));
    expect(adapter.requests, hasLength(3));
    expect(
      adapter.requests[0].queryParameters['client_id'] ?? adapter.requests[0].uri.queryParameters['client_id'],
      '1',
    );
    expect(adapter.requests[0].headers['cookie'], contains('LTP0=fixture-ticket'));
    expect(adapter.requests[1].headers['cookie'], contains('dy_did=passport-device'));
    expect(adapter.requests.last.headers['cookie'], isNot(contains('LTP0')));
    expect(result.nativeCookies.where((item) => item.cookie.name == 'dy_did'), isEmpty);
  });

  test('pasted account Cookie alone cannot manufacture a renewal credential', () async {
    final adapter = _adapter();
    await expectLater(
      _refresh(
        adapter,
        credential: const DouyuRefreshCredential(ticket: '', deviceId: 'x'),
      ),
      _failure(DouyuRefreshFailure.missingCredential),
    );
    expect(adapter.requests, isEmpty);
  });

  for (final url in [
    'http://www.douyu.com/api/passport/login',
    'https://www.douyu.com.attacker.test/api/passport/login',
    'https://passport.douyu.com@attacker.test/api/passport/login',
    'https://www.douyu.com/redirect?url=https://attacker.test',
    'https://www.douyu.com:8443/api/passport/login',
    'https://www.douyu.com/api/passport/login#fragment',
  ]) {
    test('does not send the ticket to disallowed redirect $url', () async {
      final adapter = _adapter(redirect: url);
      await expectLater(_refresh(adapter), _failure(DouyuRefreshFailure.temporary));
      expect(adapter.requests, hasLength(1));
    });
  }

  test('a different native account cannot replace the saved account', () async {
    final adapter = _adapter(cookies: _fresh(uid: '99'));
    await expectLater(_refresh(adapter), _failure(DouyuRefreshFailure.accountMismatch));
    expect(adapter.requests, hasLength(2));
  });

  test('requires every authentication field from the fresh exchange', () async {
    final cookies = _fresh().where((s) => !s.startsWith('acf_auth=')).toList();
    await expectLater(_refresh(_adapter(cookies: cookies)), _failure(DouyuRefreshFailure.loginRequired));
  });

  test('a later cookie deletion cannot be masked by an earlier good value', () async {
    await expectLater(
      _refresh(_adapter(cookies: [..._fresh(), 'acf_auth=deleted; Domain=.douyu.com; Path=/; Max-Age=0'])),
      _failure(DouyuRefreshFailure.loginRequired),
    );
  });

  for (final body in ['<html>challenge</html>', '{}', '{"error":"0"}', '{"error":null}']) {
    test('HTTP 200 with $body is not proof of successful renewal', () async {
      await expectLater(_refresh(_adapter(probe: body)), _failure(DouyuRefreshFailure.temporary));
    });
  }

  test('explicit authentication failure requires signing in again', () async {
    await expectLater(_refresh(_adapter(probe: '{"error":-1}')), _failure(DouyuRefreshFailure.loginRequired));
  });

  test('rate limits and server errors do not label the saved account expired', () async {
    await expectLater(_refresh(_adapter(status: 429)), _failure(DouyuRefreshFailure.temporary));
  });

  test('redirect loops terminate after four requests', () async {
    final adapter = _adapter(redirect: DouyuCookieRefresher.safeAuthUrl.toString());
    await expectLater(_refresh(adapter), _failure(DouyuRefreshFailure.temporary));
    expect(adapter.requests, hasLength(4));
  });

  test('playback headers retain paired DIDs and exclude passport tickets', () {
    final header = buildDouyuCookieHeader('$_original; LTP0=private', 'random');
    expect(douyuCookieDeviceId(header, 'fallback'), 'web-device');
    expect(header, contains('acf_did=web-account-device'));
    expect(header, isNot(contains('LTP0')));
    expect(douyuCookieDeviceId('', 'fallback'), 'fallback');
  });

  test('transport errors never expose credentials or response content', () async {
    final adapter = _Adapter((request) => throw StateError('fixture-ticket private-url'));
    try {
      await _refresh(adapter);
      fail('Expected a sanitized failure');
    } catch (error) {
      expect(error.toString(), isNot(contains('fixture-ticket')));
      expect(error.toString(), isNot(contains('private-url')));
    }
  });
}
