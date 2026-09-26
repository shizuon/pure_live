import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/common/services/settings/cookie_settings_controller.dart';
import 'package:pure_live/common/services/settings/bilibili_account_service.dart';

import 'platform_login_profile.dart';
import 'platform_web_session.dart';
import 'platform_web_login_page.dart';

class PlatformAccountPage extends StatefulWidget {
  const PlatformAccountPage({super.key, required this.platform});
  final String platform;
  @override
  State<PlatformAccountPage> createState() => _PlatformAccountPageState();
}

class _PlatformAccountPageState extends State<PlatformAccountPage> {
  late final _profile = PlatformLoginProfile.of(widget.platform);
  CookieSettingsController get _settings => SettingsService.to.cookieManager;
  late final _text = TextEditingController(text: _settings.accountCookie(widget.platform).value);
  bool _busy = false, _reveal = false;
  String? _message;
  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PlatformWebLoginPage(
            profile: _profile,
            onSave: (value) => _settings.setAccountCookie(widget.platform, value),
          ),
        ),
      );
      if (mounted) {
        _text.text = _settings.accountCookie(widget.platform).value;
        if (saved == true) _message = i18n('platform_login_saved');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    _settings.setAccountCookie(widget.platform, '');
    if (widget.platform == 'bilibili' && Get.isRegistered<BiliBiliAccountService>()) {
      BiliBiliAccountService.instance.clearLocalSession();
    }
    _text.clear();
    try {
      if (!PlatformUtils.isLinux) await PlatformWebSession(_profile).clear();
      _message = i18n('platform_logged_out');
    } catch (_) {
      _message = i18n('platform_logout_web_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchAccount() async {
    await _logout();
    if (mounted) await _login();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_profile.name)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(i18n('platform_login_help')),
        const SizedBox(height: 12),
        Obx(
          () => Text(
            _settings.accountCookie(widget.platform).value.isEmpty
                ? i18n('douyu_anonymous')
                : i18n('platform_session_saved'),
          ),
        ),
        if (widget.platform == 'bilibili')
          FilledButton.icon(
            onPressed: _busy ? null : () => Get.toNamed(RoutePath.kBiliBiliQRLogin),
            icon: const Icon(Icons.qr_code),
            label: Text(i18n('qr_login')),
          ),
        if (!PlatformUtils.isLinux)
          FilledButton.icon(
            key: const ValueKey('platform-web-login'),
            onPressed: _busy ? null : _login,
            icon: const Icon(Icons.login),
            label: Text(i18n('platform_sign_in', args: {'name': _profile.name})),
          )
        else
          Text(i18n('douyu_login_unsupported')),
        if (!PlatformUtils.isLinux)
          TextButton(onPressed: _busy ? null : _switchAccount, child: Text(i18n('platform_switch_account'))),
        TextButton(onPressed: _busy ? null : _logout, child: Text(i18n('douyu_cookie_clear'))),
        if (_message != null) Text(_message!),
        ExpansionTile(
          title: Text(i18n('douyu_login_advanced')),
          children: [
            Text(i18n('platform_cookie_help')),
            TextField(
              key: const ValueKey('platform-cookie-input'),
              controller: _text,
              obscureText: !_reveal,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Cookie',
                suffixIcon: IconButton(
                  tooltip: i18n('douyu_cookie_visibility'),
                  onPressed: () => setState(() => _reveal = !_reveal),
                  icon: Icon(_reveal ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () {
                      _settings.setAccountCookie(widget.platform, _text.text);
                      _text.text = _settings.accountCookie(widget.platform).value;
                      setState(() => _message = i18n('platform_login_saved'));
                    },
              child: Text(i18n('set')),
            ),
          ],
        ),
      ],
    ),
  );
}
