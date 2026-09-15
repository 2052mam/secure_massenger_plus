import '../../widgets/chat/join_privacy_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/services/storage_service.dart';

import '../../../data/services/api_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';
import 'account_switcher_screen.dart';
import 'archive_lock_screen.dart';
import 'device_management_screen.dart';
import 'admin_reports_screen.dart';
import 'sponsored_channels_screen.dart';
import 'terms_screen.dart';
import '../auth/two_factor_security_screen.dart';
import '../home/archived_chats_screen.dart';
import '../../widgets/chat/chat_labels.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';
    final themeMode = ref.watch(themeModeProvider);
    final user = ref.watch(authNotifierProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(isFa ? 'تنظیمات' : 'Settings')),
      body: SafeArea(
        child: ListView(
          children: [
            if (user != null)
              ListTile(
                leading: CircleAvatar(
                  radius: 28,
                  backgroundImage: null,
                  foregroundImage: user.avatarUrl != null
                      ? NetworkImage(
                          user.avatarUrl!,
                          headers: {
                            'Authorization':
                                'Bearer ${StorageService.getToken() ?? ""}',
                          },
                        )
                      : null,
                  child: user.avatarUrl == null
                      ? Text(
                          user.displayName.isNotEmpty
                              ? user.displayName[0]
                              : '?',
                        )
                      : null,
                ),
                title: Text(
                  user.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(user.handle),
                trailing: const Icon(Icons.chevron_left),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(isFa ? 'تم' : 'Theme'),
              subtitle: Text(
                themeMode == ThemeMode.dark
                    ? (isFa ? 'تاریک' : 'Dark')
                    : themeMode == ThemeMode.light
                    ? (isFa ? 'روشن' : 'Light')
                    : (isFa ? 'سیستم' : 'System'),
              ),
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  builder: (_) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(isFa ? 'روشن' : 'Light'),
                          onTap: () {
                            ref
                                .read(themeModeProvider.notifier)
                                .setThemeMode(ThemeMode.light);
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          title: Text(isFa ? 'تاریک' : 'Dark'),
                          onTap: () {
                            ref
                                .read(themeModeProvider.notifier)
                                .setThemeMode(ThemeMode.dark);
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          title: Text(isFa ? 'سیستم' : 'System'),
                          onTap: () {
                            ref
                                .read(themeModeProvider.notifier)
                                .setThemeMode(ThemeMode.system);
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(isFa ? 'زبان' : 'Language'),
              subtitle: Text(isFa ? 'فارسی' : 'English'),
              onTap: () async {
                final choice = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(isFa ? 'انتخاب زبان' : 'Choose language'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: const Text('فارسی'),
                          leading: Radio<String>(
                            value: 'fa',
                            groupValue: isFa ? 'fa' : 'en',
                            onChanged: (v) => Navigator.pop(ctx, v),
                          ),
                          onTap: () => Navigator.pop(ctx, 'fa'),
                        ),
                        ListTile(
                          title: const Text('English'),
                          leading: Radio<String>(
                            value: 'en',
                            groupValue: isFa ? 'fa' : 'en',
                            onChanged: (v) => Navigator.pop(ctx, v),
                          ),
                          onTap: () => Navigator.pop(ctx, 'en'),
                        ),
                      ],
                    ),
                  ),
                );
                if (choice == 'fa') {
                  ref
                      .read(localeProvider.notifier)
                      .setLocale(const Locale('fa', 'IR'));
                } else if (choice == 'en') {
                  ref
                      .read(localeProvider.notifier)
                      .setLocale(const Locale('en', 'US'));
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: Text(isFa ? 'حالت گوست' : 'Ghost Mode'),
              subtitle: Text(
                isFa
                    ? 'پنهان کردن وضعیت آنلاین و آخرین بازدید'
                    : 'Hide online status & last seen',
              ),
              trailing: Switch(
                value: !(user?.showLastSeen ?? true),
                onChanged: (v) async {
                  try {
                    await ApiService().put('/users/me', {'show_last_seen': !v});
                    ref.read(authNotifierProvider.notifier).checkSession();
                  } catch (_) {}
                },
              ),
            ),
            const JoinPrivacyTile(),
            ListTile(
              key: const ValueKey('two-factor-security-tile'),
              leading: const Icon(Icons.security_outlined),
              title: Text(isFa ? 'تأیید دو مرحله‌ای' : 'Two-Step Verification'),
              subtitle: Text(
                user?.isTwoFactorEnabled == true
                    ? (isFa ? 'Google Authenticator فعال است' : 'Google Authenticator is enabled')
                    : (isFa ? 'اختیاری — ورود اصلی با پیامک است' : 'Optional — SMS remains the primary sign-in'),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TwoFactorSecurityScreen()),
              ),
            ),
            ListTile(
              key: const ValueKey('archive-lock-tile'),
              leading: const Icon(Icons.lock_outline),
              title: Text(ChatLabels.of(context).archiveLock),
              subtitle: Text(ChatLabels.of(context).archiveLockHint),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ArchiveLockScreen()),
              ),
            ),
            ListTile(
              key: const ValueKey('archived-chats-tile'),
              leading: const Icon(Icons.archive_outlined),
              title: Text(ChatLabels.of(context).archivedChats),
              onTap: () => openArchivedChats(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: Text(isFa ? 'دستگاه‌ها و نشست‌ها' : 'Devices & Sessions'),
              subtitle: Text(isFa ? 'مدیریت ورود چنددستگاهی مانند تلگرام' : 'Manage multi-device logins like Telegram'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeviceManagementScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.report_outlined, color: Colors.orange),
              title: Text(isFa ? 'گزارش‌ها (مدیریت)' : 'Reports (Admin)'),
              subtitle: Text(isFa ? 'بررسی گزارش کاربران و گروه‌ها/کانال‌ها' : 'Review user & chat reports'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminReportsScreen())),
            ),
            if (user?.isAdmin == true)
              ListTile(
                leading: const Icon(Icons.campaign_outlined, color: Colors.amber),
                title: const Text('کانال‌های اسپانسرشده'),
                subtitle: const Text('مدیریت کانال‌های تبلیغاتی (مدیر کل)', style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SponsoredChannelsScreen()),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.forward_outlined),
              title: Text(isFa ? 'اجازه فوروارد پیام‌های من' : 'Allow forwarding my messages'),
              subtitle: Text(isFa ? 'دیگران بتوانند پیام‌های شما را فوروارد کنند' : 'Others can forward your messages'),
              trailing: Switch(
                value: user?.allowForwarding ?? true,
                onChanged: (v) async {
                  try {
                    await ApiService().put('/users/me', {'allow_forwarding': v});
                    ref.read(authNotifierProvider.notifier).checkSession();
                  } catch (_) {}
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.rule_outlined),
              title: Text(isFa ? 'قوانین و مقررات' : 'Rules & Terms'),
              subtitle: Text(isFa ? 'قوانین استفاده از پیام‌رسان' : 'Messenger rules of use'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TermsScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: Text(isFa ? 'نمایش عکس پروفایل' : 'Show Profile Photo'),
              trailing: Switch(
                value: user?.showProfilePhoto ?? true,
                onChanged: (v) async {
                  try {
                    await ApiService().put('/users/me', {
                      'show_profile_photo': v,
                    });
                    ref.read(authNotifierProvider.notifier).checkSession();
                  } catch (_) {}
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: Text(isFa ? 'افراد بلاک شده' : 'Blocked Users'),
              onTap: () async {
                try {
                  final res = await ApiService().get('/users/blocked');
                  final users = res['users'] as List? ?? [];
                  if (!context.mounted) return;
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(isFa ? 'بلاک شده‌ها' : 'Blocked Users'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: users.isEmpty
                            ? Text(isFa ? 'کسی بلاک نشده' : 'No blocked users')
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: users.length,
                                itemBuilder: (_, i) {
                                  final u = users[i];
                                  return ListTile(
                                    title: Text(u['display_name'] ?? ''),
                                    subtitle: Text('@${u['username'] ?? ''}'),
                                    trailing: TextButton(
                                      child: const Text(
                                        'آنبلاک',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                      onPressed: () async {
                                        await ApiService().post(
                                          '/users/unblock/${u['id']}',
                                          {},
                                        );
                                        Navigator.pop(ctx);
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('بستن'),
                        ),
                      ],
                    ),
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.switch_account),
              title: Text(isFa ? 'مدیریت اکانت‌ها' : 'Accounts'),
              subtitle: Text(
                isFa ? 'سوییچ بین حداکثر ۳ اکانت' : 'Switch up to 3 accounts',
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccountSwitcherScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: Text(isFa ? 'چت با پشتیبانی' : 'Support Chat'),
              onTap: () async {
                try {
                  final res = await ApiService().post('/chats/support', {});
                  final chatId = res['chat_id'] as String;
                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: chatId,
                          title: isFa ? 'پشتیبانی' : 'Support',
                          chatType: 'support',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
            ),

            ListTile(
              leading: const Icon(Icons.bookmark_outline),
              title: Text(isFa ? 'پیام‌های ذخیره‌شده' : 'Saved Messages'),
              onTap: () async {
                try {
                  final res = await ApiService().post('/chats/saved', {});
                  final chatId = res['chat_id'] as String;
                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: chatId,
                          title: isFa ? 'پیام‌های ذخیره‌شده' : 'Saved Messages',
                          chatType: 'saved',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(
                isFa ? 'خروج از حساب' : 'Logout',
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(isFa ? 'خروج' : 'Logout'),
                    content: Text(isFa ? 'آیا مطمئن هستید؟' : 'Are you sure?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(isFa ? 'خیر' : 'No'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(isFa ? 'بله' : 'Yes'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref.read(authNotifierProvider.notifier).logout();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
