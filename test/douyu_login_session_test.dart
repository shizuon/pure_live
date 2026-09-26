import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/douyu/douyu_cookie.dart';
import 'package:pure_live/modules/account/douyu/douyu_login_session.dart';

void main() {
  test('normalizes pasted cookie, preserves token equals, replaces stale DID', () {
    final cookie = buildDouyuCookieHeader(
      'Cookie: acf_auth=abc==;\r\n acf_uid=123; dy_did=old; ACF_DID=other; broken; bad name=x',
      'session-device',
    );
    expect(cookie, 'dy_did=session-device; acf_did=session-device; acf_auth=abc==; acf_uid=123');
    expect(hasDouyuAccountSession(cookie), isTrue);
    expect(hasDouyuAccountSession('acf_auth=x; acf_uid=0'), isFalse);
    expect(hasDouyuAccountSession('dy_did=x; acf_uid=123'), isFalse);
    expect(hasDouyuAccountSession('acf_auth=deleted; acf_uid=123'), isFalse);
  });

  test('only HTTPS Douyu navigation is allowed', () {
    for (final url in ['https://passport.douyu.com/member/login', 'https://www.douyu.com/']) {
      expect(isDouyuLoginUrl(Uri.parse(url)), isTrue);
    }
    for (final url in [
      'https://douyu.com.example.org/',
      'https://fakedouyu.com/',
      'http://www.douyu.com/',
      'file:///tmp/a',
    ]) {
      expect(isDouyuLoginUrl(Uri.parse(url)), isFalse);
    }
  });

  test('visitor cookies do not complete sign-in; account session saves once', () async {
    var value = 'dy_did=x';
    final saved = <String>[];
    final session = DouyuLoginSession(readCookies: () async => value, save: saved.add);
    expect(await session.check(), isFalse);
    expect(saved, isEmpty);
    value = 'acf_auth=token; acf_uid=42';
    expect(await session.check(), isTrue);
    expect(await session.check(), isFalse);
    expect(saved, [value]);
    session.dispose();
  });

  test('overlapping checks and late completion after closing cannot save', () async {
    final pending = Completer<String>();
    var reads = 0;
    final saved = <String>[];
    final session = DouyuLoginSession(
      readCookies: () {
        reads++;
        return pending.future;
      },
      save: saved.add,
    );
    final active = session.check();
    expect(await session.check(), isFalse);
    expect(reads, 1);
    session.dispose();
    pending.complete('acf_auth=token; acf_uid=42');
    expect(await active, isFalse);
    expect(saved, isEmpty);
  });

  test('cookie store error allows a later retry', () async {
    var fail = true;
    final saved = <String>[];
    final session = DouyuLoginSession(
      readCookies: () async {
        if (fail) throw StateError('fixture');
        return 'acf_auth=token; acf_uid=42';
      },
      save: saved.add,
    );
    await expectLater(session.check(), throwsStateError);
    fail = false;
    expect(await session.check(), isTrue);
    expect(saved, hasLength(1));
  });
}
