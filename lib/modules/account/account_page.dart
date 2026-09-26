import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/account/account_controller.dart';
import 'package:pure_live/common/services/settings/bilibili_account_service.dart';

import 'platform_account_page.dart';
import 'platform_login_profile.dart';

class AccountPage extends GetView<AccountController> {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(i18n('third_party_auth'))),
    body: ListView(
      physics: const PureLiveScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        context.buildGroupTitle(i18n('third_party_auth')),
        context.buildModernCard([
          Obx(() {
            final service = BiliBiliAccountService.instance;
            return ListTile(
              leading: Image.asset('assets/images/bilibili_2.png', width: 24, height: 24),
              title: Text(i18n('site_bilibili')),
              subtitle: Text(service.logined.value ? service.name.value : i18n('qr_login')),
              trailing: IconButton(
                tooltip: service.logined.value ? i18n('logout') : i18n('qr_login'),
                icon: Icon(service.logined.value ? Icons.logout : Icons.qr_code),
                onPressed: () => service.logined.value ? _logoutBilibili(context) : controller.bilibiliTap(),
              ),
              onTap: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PlatformAccountPage(platform: 'bilibili'))),
            );
          }),
          for (final profile in PlatformLoginProfile.profiles.where((p) => p.id != 'bilibili'))
            Obx(
              () => ListTile(
                key: ValueKey('account-${profile.id}'),
                leading: Image.asset('assets/images/${profile.id}.png', width: 24, height: 24),
                title: Text(profile.name),
                subtitle: Text(
                  controller.cookie.accountCookie(profile.id).value.isEmpty
                      ? i18n('platform_sign_in', args: {'name': profile.name})
                      : i18n('platform_session_saved'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => PlatformAccountPage(platform: profile.id))),
              ),
            ),
          ListTile(title: const Text('Kick · YouTube · CC · IPTV'), subtitle: Text(i18n('platform_anonymous_only'))),
        ]),
      ],
    ),
  );

  Future<void> _logoutBilibili(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n('logout')),
        content: Text(i18n('confirm_logout')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(i18n('confirm'))),
        ],
      ),
    );
    if (confirmed == true) await BiliBiliAccountService.instance.logout();
  }
}
