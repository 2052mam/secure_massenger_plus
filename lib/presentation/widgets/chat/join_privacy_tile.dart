import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';

class JoinPrivacyTile extends ConsumerStatefulWidget {
  const JoinPrivacyTile({super.key});
  @override
  ConsumerState<JoinPrivacyTile> createState() => _JoinPrivacyTileState();
}

class _JoinPrivacyTileState extends ConsumerState<JoinPrivacyTile> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';
    final user = ref.watch(authNotifierProvider).valueOrNull;
    return SwitchListTile(
      secondary: const Icon(Icons.group_add_outlined),
      title: Text(
        isFa ? 'اجازه افزودن به گروه و کانال' : 'Allow people to join',
      ),
      subtitle: Text(
        isFa
            ? 'اجازه دهید افراد فهرست چت شما را اضافه کنند. اگر خاموش باشد، فقط لینک دعوت دریافت می‌کنید.'
            : 'Let chat-list contacts add you to groups and channels. When off, you only receive an invite link.',
      ),
      value: user?.allowGroupAdds ?? true,
      onChanged: _saving || user == null
          ? null
          : (value) async {
              final session = ref.read(authenticatedSessionProvider);
              setState(() => _saving = true);
              try {
                await session.api.put('/users/me', {'allow_group_adds': value});
                if (!mounted) return;
                if (ref.read(authenticatedSessionProvider).userId ==
                    session.userId) {
                  await ref.read(authNotifierProvider.notifier).checkSession();
                }
              } catch (error) {
                if (mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$error')));
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
    );
  }
}
