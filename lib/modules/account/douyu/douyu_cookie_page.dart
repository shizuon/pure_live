import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/global/platform_utils.dart';

import 'douyu_web_login_page.dart';

class DouyuCookiePage extends StatefulWidget {
  const DouyuCookiePage({super.key});

  @override
  State<DouyuCookiePage> createState() => _DouyuCookiePageState();
}

class _DouyuCookiePageState extends State<DouyuCookiePage> {
  late final _text = TextEditingController(text: SettingsService.to.cookieManager.douyuCookie.value);
  bool _visible = false;
  bool _saved = false;
  bool _busy = false;

  void _save() {
    final settings = SettingsService.to.cookieManager;
    settings.setDouyuCookie(_text.text);
    _text.text = settings.douyuCookie.value;
    setState(() => _saved = true);
  }

  Future<void> _login() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const DouyuWebLoginPage()));
    if (!mounted) return;
    _text.text = SettingsService.to.cookieManager.douyuCookie.value;
    setState(() => _saved = saved == true);
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    SettingsService.to.cookieManager.setDouyuCookie('');
    _text.clear();
    try {
      if (!PlatformUtils.isLinux) await DouyuWebSession.clear();
      if (mounted) setState(() => _saved = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n('douyu_logout_web_failed'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(i18n('douyu_login'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(i18n('douyu_login_help')),
        const SizedBox(height: 16),
        if (!PlatformUtils.isLinux)
          FilledButton.icon(
            key: const ValueKey('douyu-web-login'),
            onPressed: _busy ? null : _login,
            icon: const Icon(Icons.login),
            label: Text(i18n('douyu_login')),
          )
        else
          Text(i18n('douyu_login_unsupported')),
        Obx(
          () => Text(
            SettingsService.to.cookieManager.douyuCookie.value.isEmpty
                ? i18n('douyu_anonymous')
                : i18n('douyu_cookie_stored'),
          ),
        ),
        TextButton(
          key: const ValueKey('douyu-cookie-clear'),
          onPressed: _busy ? null : _clear,
          child: Text(i18n('douyu_cookie_clear')),
        ),
        if (_saved) Text(i18n('douyu_cookie_saved_hint')),
        const SizedBox(height: 20),
        ExpansionTile(
          title: Text(i18n('douyu_login_advanced')),
          children: [
            Padding(padding: const EdgeInsets.all(12), child: Text(i18n('douyu_cookie_help'))),
            TextField(
              key: const ValueKey('douyu-cookie-input'),
              controller: _text,
              obscureText: !_visible,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() => _saved = false),
              decoration: InputDecoration(
                labelText: 'Cookie',
                suffixIcon: IconButton(
                  tooltip: i18n('douyu_cookie_visibility'),
                  onPressed: () => setState(() => _visible = !_visible),
                  icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(key: const ValueKey('douyu-cookie-save'), onPressed: _save, child: Text(i18n('set'))),
          ],
        ),
      ],
    ),
  );
}
