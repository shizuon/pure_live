import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/services/douyu_account_refresh_service.dart';
import 'package:pure_live/common/services/settings/cookie_settings_controller.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/site/douyu/douyu_cookie_refresh.dart';

const _old = 'acf_uid=42; acf_auth=old';
const _new = DouyuCookieRefreshResult(cookie: 'acf_uid=42; acf_auth=new');
const _credential = DouyuRefreshCredential(ticket: 'fixture', deviceId: 'fixture-device');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late CookieSettingsController settings;
  late DouyuAccountRefreshService service;
  late DateTime now;
  var writes = 0, requests = 0, reads = 0;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('douyu-refresh-test');
    Hive.init(temp.path);
    await HivePrefUtil.init();
    settings = Get.put(CookieSettingsController());
    settings.setDouyuCookie(_old);
    now = DateTime.utc(2026, 11, 2);
    writes = requests = reads = 0;
  });
  tearDown(() async {
    service.onClose();
    await service.cancelAndWait();
    Get.reset();
    await Hive.close();
    await temp.delete(recursive: true);
  });

  DouyuAccountRefreshService create({
    Future<DouyuCookieRefreshResult> Function()? exchange,
    Future<void> Function(bool Function())? write,
    bool missing = false,
  }) => DouyuAccountRefreshService(
    settings: settings,
    now: () => now,
    readCredential: () async {
      reads++;
      return missing ? null : _credential;
    },
    exchange: (_, _, _) async {
      requests++;
      return exchange == null ? _new : await exchange();
    },
    writeNativeCookies: (_, current) async {
      writes++;
      if (write != null) await write(current);
    },
  );

  test('refreshes once after startup and persists the newly verified account', () async {
    service = create();
    await service.refreshOnStartup();
    await service.refreshOnStartup();
    expect(settings.douyuCookie.value, _new.cookie);
    expect(service.status.value, DouyuRefreshStatus.refreshed);
    expect(service.lastSuccess.value, now);
    expect(requests, 1);
    expect(writes, 1);
    await Hive.box('app_settings').flush();
    expect(CookieSettingsController().douyuCookie.value, _new.cookie);
    expect(settings.toJson(), isNot(contains('douyuCookie')));
  });

  test('anonymous startup never reads the native store or auto logs in', () async {
    settings.setDouyuCookie('');
    service = create();
    await service.refreshOnStartup();
    expect(reads, 0);
    expect(requests, 0);
    expect(service.status.value, DouyuRefreshStatus.idle);
  });

  test('missing long-term credentials preserves a manually imported account', () async {
    service = create(missing: true);
    await service.refreshOnStartup();
    expect(settings.douyuCookie.value, _old);
    expect(service.status.value, DouyuRefreshStatus.unavailable);
    expect(requests, 0);
  });

  test('concurrent requests share one exchange; manual retries are limited', () async {
    final result = Completer<DouyuCookieRefreshResult>();
    service = create(exchange: () => result.future);
    final first = service.refresh();
    final second = service.refresh();
    expect(identical(first, second), isTrue);
    result.complete(_new);
    await first;
    await service.refresh();
    expect(requests, 1);
    now = now.add(const Duration(minutes: 2));
    await service.refresh();
    expect(requests, 2);
  });

  for (final replacement in ['', 'acf_uid=99; acf_auth=other', _old]) {
    test('an explicit account change invalidates an old result: $replacement', () async {
      final result = Completer<DouyuCookieRefreshResult>();
      final started = Completer<void>();
      service = create(
        exchange: () {
          started.complete();
          return result.future;
        },
      );
      final run = service.refresh();
      await started.future;
      settings.setDouyuCookie(replacement);
      result.complete(_new);
      await run;
      expect(settings.douyuCookie.value, replacement);
      expect(writes, 0);
    });
  }

  test('failure leaves the saved cookie intact and a later retry can succeed', () async {
    var fail = true;
    service = create(
      exchange: () async {
        if (fail) throw const DouyuRefreshException(DouyuRefreshFailure.temporary);
        return _new;
      },
    );
    await service.refreshOnStartup();
    expect(settings.douyuCookie.value, _old);
    expect(service.status.value, DouyuRefreshStatus.failed);
    fail = false;
    now = now.add(const Duration(minutes: 2));
    await service.refresh();
    expect(settings.douyuCookie.value, _new.cookie);
  });

  test('logout drains an in-flight native write before clearing the cookie store', () async {
    final writing = Completer<void>();
    final finish = Completer<void>();
    service = create(
      write: (current) async {
        writing.complete();
        await finish.future;
        expect(current(), isFalse);
      },
    );
    final run = service.refresh();
    await writing.future;
    settings.setDouyuCookie('');
    var drained = false;
    final cancel = service.cancelAndWait().then((_) => drained = true);
    expect(drained, isFalse);
    finish.complete();
    await cancel;
    await run;
    expect(settings.douyuCookie.value, isEmpty);
    expect(drained, isTrue);
  });

  test('closing the service invalidates an outstanding exchange', () async {
    final result = Completer<DouyuCookieRefreshResult>();
    final started = Completer<void>();
    service = create(
      exchange: () {
        started.complete();
        return result.future;
      },
    );
    final run = service.refresh();
    await started.future;
    service.onClose();
    result.complete(_new);
    await run;
    expect(settings.douyuCookie.value, _old);
    expect(writes, 0);
  });
}
