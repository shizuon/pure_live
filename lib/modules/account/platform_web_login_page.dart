import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/site/douyu/douyu_cookie.dart';

import 'platform_login_profile.dart';
import 'platform_web_session.dart';

/// This gate has no UI/plugin dependency and prevents late reads from saving a
/// previous account after route close, logout or a replacement login.
class PlatformLoginCapture {
  PlatformLoginCapture({required this.read, required this.accept, required this.save});
  final Future<String> Function() read;
  final bool Function(String) accept;
  final void Function(String) save;
  bool _closed = false, _busy = false, _saved = false;
  Future<bool> check() async {
    if (_closed || _busy || _saved) return false;
    _busy = true;
    try {
      final value = normalizeDouyuCookie(await read());
      if (_closed || _saved || !accept(value)) return false;
      save(value);
      _saved = true;
      return true;
    } finally {
      _busy = false;
    }
  }

  void close() => _closed = true;
}

class PlatformWebLoginPage extends StatefulWidget {
  const PlatformWebLoginPage({super.key, required this.profile, required this.onSave});
  final PlatformLoginProfile profile;
  final void Function(String) onSave;
  @override
  State<PlatformWebLoginPage> createState() => _PlatformWebLoginPageState();
}

class _PlatformWebLoginPageState extends State<PlatformWebLoginPage> with WidgetsBindingObserver {
  Timer? _timer;
  late final PlatformLoginCapture _capture;
  InAppWebViewController? _web;
  bool _foreground = true, _busy = false, _failed = false, _finished = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _capture = PlatformLoginCapture(
      read: PlatformWebSession(widget.profile).read,
      accept: widget.profile.hasSession,
      save: widget.onSave,
    );
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_foreground && ModalRoute.of(context)?.isCurrent == true) unawaited(_check());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _foreground = state == AppLifecycleState.resumed;
  Future<void> _check({bool manual = false}) async {
    if (!mounted || _busy || _finished) return;
    setState(() => _busy = true);
    try {
      if (await _capture.check()) {
        if (!mounted) return;
        _finished = true;
        _timer?.cancel();
        Navigator.of(context).pop(true);
      } else if (manual && mounted) {
        setState(() => _message = i18n('platform_login_not_ready'));
      }
    } catch (_) {
      if (mounted && manual) setState(() => _message = i18n('platform_login_read_failed'));
    } finally {
      if (mounted && !_finished) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _capture.close();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(i18n('platform_sign_in', args: {'name': widget.profile.name})),
      actions: [
        TextButton(onPressed: _busy ? null : () => _check(manual: true), child: Text(i18n('douyu_login_done'))),
      ],
    ),
    body: Column(
      children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(_message ?? i18n('platform_login_web_help'))),
        if (_failed)
          TextButton(
            onPressed: () {
              setState(() => _failed = false);
              _web?.loadUrl(urlRequest: URLRequest(url: WebUri(widget.profile.loginUrl)));
            },
            child: Text(i18n('retry')),
          ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.profile.loginUrl)),
            initialSettings: InAppWebViewSettings(
              useShouldOverrideUrlLoading: true,
              supportMultipleWindows: false,
              javaScriptCanOpenWindowsAutomatically: false,
            ),
            onWebViewCreated: (controller) => _web = controller,
            shouldOverrideUrlLoading: (_, action) async {
              final allowed =
                  widget.profile.allows(action.request.url) ||
                  (!action.isForMainFrame && action.request.url?.scheme == 'https');
              return allowed ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL;
            },
            onLoadStop: (_, uri) async {
              if (widget.profile.allows(uri)) await _check();
            },
            onReceivedError: (_, request, error) {
              if (mounted && request.isForMainFrame == true) {
                setState(() {
                  _failed = true;
                  _message = i18n('platform_login_load_failed');
                });
              }
            },
          ),
        ),
      ],
    ),
  );
}
