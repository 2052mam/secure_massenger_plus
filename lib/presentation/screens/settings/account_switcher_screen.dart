import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/account_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../auth/login_screen.dart';
import '../home/main_shell.dart';
import '../../widgets/chat/chat_avatar.dart';

class AccountSwitcherScreen extends ConsumerStatefulWidget {
  const AccountSwitcherScreen({super.key});

  @override
  ConsumerState<AccountSwitcherScreen> createState() =>
      _AccountSwitcherScreenState();
}

class _AccountSwitcherScreenState extends ConsumerState<AccountSwitcherScreen> {
  List<SavedAccount> _accounts = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AccountService.list();
    if (!mounted) return;
    setState(() {
      _accounts = list;
      _loading = false;
    });
  }

  Future<void> _switchTo(SavedAccount account) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final previousId = ref.read(authNotifierProvider).valueOrNull?.id;
      await ref.read(authNotifierProvider.notifier).switchAccount(account);
      if (!mounted) return;
      // Different identities reset the Navigator in app.dart. Selecting the
      // current account needs only to return to its chat list.
      if (previousId == account.userId) {
        ref.read(shellIndexProvider.notifier).state = 0;
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addAccount() async {
    if (_busy) return;
    // Adding an account must NOT sign the current one out: previously this
    // called logoutKeepAccounts(), which destroyed the session and left the
    // login screen as the only route — so "back" had nowhere to return to.
    // Now it is an ordinary pushed route that can simply be popped.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(isAddAccount: true),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _removeAccount(SavedAccount account) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (ref.read(authNotifierProvider).valueOrNull?.id == account.userId) {
        await ref.read(authNotifierProvider.notifier).logout();
      } else {
        await AccountService.remove(account.userId);
        await _load();
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';

    return Scaffold(
      appBar: AppBar(
        title: Text(isFa ? 'مدیریت اکانت‌ها' : 'Accounts'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ..._accounts.map(
                  (a) => ListTile(
                    leading: ChatAvatar(
                      title: a.displayName,
                      url: a.avatarUrl,
                      token: a.accessToken,
                    ),
                    title: Text(a.displayName),
                    subtitle: Text(a.handle),
                    trailing: IconButton(
                      icon: const Icon(Icons.logout, size: 20),
                      onPressed: _busy ? null : () => _removeAccount(a),
                    ),
                    onTap: _busy ? null : () => _switchTo(a),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text(isFa ? 'افزودن اکانت' : 'Add account'),
                  subtitle: Text(isFa ? 'حداکثر ۳ اکانت' : 'Max 3 accounts'),
                  onTap: _busy
                      ? null
                      : _accounts.length >= 3
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isFa ? 'حداکثر ۳ اکانت' : 'Max 3 accounts',
                              ),
                            ),
                          );
                        }
                      : _addAccount,
                ),
              ],
            ),
    );
  }
}
