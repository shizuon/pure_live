import 'dart:async';

import 'package:dio/dio.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/site/douyu/douyu_cookie.dart';
import 'package:pure_live/core/site/douyu/douyu_cookie_refresh.dart';

import 'settings/cookie_settings_controller.dart';

enum DouyuRefreshStatus { idle, refreshing, refreshed, loginRequired, unavailable, failed }

typedef DouyuCookieExchange = Future<DouyuCookieRefreshResult> Function(
  String accountCookie,
  DouyuRefreshCredential credential,
  CancelToken cancelToken,
);

/// One bounded background exchange per launch. The epoch and settings revision
/// fence every async boundary; account UI cancels/drains before touching the
/// shared native cookie store. Neither failures nor logout restore old values.
class DouyuAccountRefreshService extends GetxService {
  DouyuAccountRefreshService({
    required this.settings,
    required this.readCredential,
    required this.exchange,
    required this.writeNativeCookies,
    this.timeout = const Duration(seconds: 40),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final CookieSettingsController settings;
  final Future<DouyuRefreshCredential?> Function() readCredential;
  final DouyuCookieExchange exchange;
  final Future<void> Function(List<DouyuRefreshedCookie>, bool Function()) writeNativeCookies;
  final Duration timeout;
  final DateTime Function() _now;
  final status = DouyuRefreshStatus.idle.obs;
  final lastSuccess = Rxn<DateTime>();
  Future<void>? _active;
  CancelToken? _cancelToken;
  int _epoch = 0;
  bool _closed = false, _startupScheduled = false;
  DateTime? _lastAttempt;

  Future<void> refreshOnStartup() {
    if (_startupScheduled) return _active ?? Future.value();
    _startupScheduled = true;
    return refresh();
  }

  Future<void> refresh() {
    if (_closed) return Future.value();
    if (_active != null) return _active!;
    final original = settings.douyuCookie.value;
    final fields = douyuCookieFields(original);
    if ((int.tryParse(fields['acf_uid'] ?? '') ?? 0) <= 0 || fields['acf_auth']?.isNotEmpty != true) {
      status.value = DouyuRefreshStatus.idle;
      return Future.value();
    }
    // Manual retries share the same flight and have a bounded minimum gap.
    final now = _now();
    if (_lastAttempt != null && now.difference(_lastAttempt!) < const Duration(minutes: 1)) return Future.value();
    _lastAttempt = now;
    final epoch = ++_epoch;
    final revision = settings.douyuSessionRevision;
    final token = CancelToken();
    _cancelToken = token;
    bool current() =>
        !_closed &&
        !token.isCancelled &&
        _epoch == epoch &&
        settings.douyuSessionRevision == revision &&
        settings.douyuCookie.value == original;

    status.value = DouyuRefreshStatus.refreshing;
    final run = _run(original, token, current);
    _active = run;
    // Cleanup attaches before the caller awaits, including synchronous fakes.
    unawaited(
      run.whenComplete(() {
        if (identical(_active, run)) {
          _active = null;
          _cancelToken = null;
        }
      }),
    );
    return run;
  }

  Future<void> _run(String original, CancelToken token, bool Function() current) async {
    final deadline = Timer(timeout, () {
      if (current()) status.value = DouyuRefreshStatus.failed;
      token.cancel();
    });
    try {
      final credential = await readCredential().timeout(timeout);
      if (!current()) return;
      if (credential == null) {
        status.value = DouyuRefreshStatus.unavailable;
        return;
      }
      final result = await exchange(original, credential, token).timeout(timeout);
      if (!current()) return;
      final oldUid = douyuCookieFields(original)['acf_uid'];
      final newFields = douyuCookieFields(result.cookie);
      if (newFields['acf_uid'] != oldUid || newFields['acf_auth']?.isNotEmpty != true) {
        throw const DouyuRefreshException(DouyuRefreshFailure.accountMismatch);
      }
      await writeNativeCookies(result.nativeCookies, current);
      if (!current()) return;
      settings.setDouyuCookie(result.cookie);
      lastSuccess.value = _now();
      status.value = DouyuRefreshStatus.refreshed;
    } on DouyuRefreshException catch (error) {
      if (!current()) return;
      status.value = switch (error.failure) {
        DouyuRefreshFailure.missingCredential => DouyuRefreshStatus.unavailable,
        DouyuRefreshFailure.loginRequired || DouyuRefreshFailure.accountMismatch => DouyuRefreshStatus.loginRequired,
        DouyuRefreshFailure.temporary => DouyuRefreshStatus.failed,
      };
    } catch (_) {
      if (current()) status.value = DouyuRefreshStatus.failed;
    } finally {
      deadline.cancel();
      if (status.value == DouyuRefreshStatus.refreshing && !current()) status.value = DouyuRefreshStatus.idle;
    }
  }

  Future<void> cancelAndWait() async {
    _epoch++;
    _cancelToken?.cancel();
    status.value = DouyuRefreshStatus.idle;
    _lastAttempt = null;
    await _active;
  }

  @override
  void onClose() {
    _closed = true;
    _epoch++;
    _cancelToken?.cancel();
    super.onClose();
  }
}
