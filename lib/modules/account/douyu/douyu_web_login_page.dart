import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/site/douyu/douyu_utils.dart';

import 'douyu_login_session.dart';

/// Uses the existing app WebView's native cookie store, including HttpOnly
/// cookies. Does not inspect passwords, inject login JS, or access a browser.
class DouyuWebSession {
  static const roomUrl = 'https://www.douyu.com/';
  static const loginUrl = 'https://passport.douyu.com/member/login';

  static Future<String> read() async {
    final cookies = await CookieManager.instance().getCookies(url: WebUri(roomUrl));
    // The native cookie store already filters applicable cookies. Do not
    // reinterpret expiresDate: this pinned Windows plugin exposes CDP seconds
    // and session=-1, while WKWebView uses milliseconds/null.
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  static Future<void> clear() async {
    // Never call deleteAllCookies: other platforms share this native store.
    final manager = CookieManager.instance();
    for (final url in [roomUrl, loginUrl, 'https://m.douyu.com/']) {
      final cookies = await manager.getCookies(url: WebUri(url));
      for (final cookie in cookies) {
        final deleted = await manager.deleteCookie(
          url: WebUri(url),
          name: cookie.name,
          domain: cookie.domain,
          path: cookie.path ?? '/',
        );
        if (!deleted) throw StateError('Douyu web session was not cleared');
      }
    }
  }
}

class DouyuWebLoginPage extends StatefulWidget {
  const DouyuWebLoginPage({super.key});

  @override
  State<DouyuWebLoginPage> createState() => _DouyuWebLoginPageState();
}

class _DouyuWebLoginPageState extends State<DouyuWebLoginPage> with WidgetsBindingObserver {
  late final DouyuLoginSession _session;
  Timer? _timer;
  bool _checking = false;
  bool _visible = true;
  bool _failed = false;
  String? _message;
  InAppWebViewController? _web;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = DouyuLoginSession(
      readCookies: DouyuWebSession.read,
      save: SettingsService.to.cookieManager.setDouyuCookie,
    );
    // Only exists while this login route is mounted and foregrounded.
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_visible && ModalRoute.of(context)?.isCurrent == true) unawaited(_check());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
  }

  Future<void> _check({bool manual = false}) async {
    if (_checking || !mounted) return;
    setState(() => _checking = true);
    try {
      final saved = await _session.check();
      if (!mounted) return;
      if (saved) {
        _timer?.cancel();
        Navigator.of(context).pop(true);
      } else if (manual) {
        setState(() => _message = i18n('douyu_login_not_ready'));
      }
    } catch (_) {
      // Do not log cookie store results or platform errors containing tokens.
      if (mounted && manual) setState(() => _message = i18n('douyu_login_read_failed'));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _session.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(i18n('douyu_login')),
      actions: [
        TextButton(onPressed: _checking ? null : () => _check(manual: true), child: Text(i18n('douyu_login_done'))),
      ],
    ),
    body: Column(
      children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(_message ?? i18n('douyu_web_login_help'))),
        if (_failed)
          TextButton(
            onPressed: () {
              setState(() => _failed = false);
              _web?.loadUrl(urlRequest: URLRequest(url: WebUri(DouyuWebSession.loginUrl)));
            },
            child: Text(i18n('retry')),
          ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(DouyuWebSession.loginUrl)),
            initialSettings: InAppWebViewSettings(
              userAgent: DouyuUtils.userAgent,
              useShouldOverrideUrlLoading: true,
              supportMultipleWindows: false,
              javaScriptCanOpenWindowsAutomatically: false,
            ),
            onWebViewCreated: (controller) => _web = controller,
            shouldOverrideUrlLoading: (_, action) async {
              // Captcha providers can use HTTPS subframes. The top-level page
              // and any session-completion event must still belong to Douyu.
              final allowed =
                  isDouyuLoginUrl(action.request.url) ||
                  (!action.isForMainFrame && action.request.url?.scheme == 'https');
              return allowed ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL;
            },
            onLoadStop: (_, uri) async {
              if (isDouyuLoginUrl(uri)) await _check();
            },
            onReceivedError: (_, request, error) {
              if (mounted && request.isForMainFrame == true) {
                setState(() {
                  _failed = true;
                  _message = i18n('douyu_login_load_failed');
                });
              }
            },
          ),
        ),
      ],
    ),
  );
}
