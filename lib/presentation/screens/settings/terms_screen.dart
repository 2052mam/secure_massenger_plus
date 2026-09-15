import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/locale_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/services/terms_service.dart';

/// Settings → Rules page (readable rules + acceptance state).
class TermsScreen extends ConsumerWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';
    final user = ref.watch(authNotifierProvider).valueOrNull;
    final rules = TermsService.rulesFor(isFa ? 'fa' : 'en');
    return Scaffold(
      appBar: AppBar(title: Text(isFa ? 'قوانین برنامه' : 'App Rules')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
              ),
              child: Text(rules, style: const TextStyle(fontSize: 13.5, height: 1.8)),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(
                (user?.termsVersion ?? 0) >= TermsService.currentVersion
                    ? Icons.verified_outlined
                    : Icons.pending_outlined,
                color: (user?.termsVersion ?? 0) >= TermsService.currentVersion
                    ? Colors.green
                    : Colors.orange,
              ),
              title: Text(isFa ? 'وضعیت پذیرش' : 'Acceptance status'),
              subtitle: Text(
                (user?.termsVersion ?? 0) >= TermsService.currentVersion
                    ? (isFa ? 'شما قوانین (نسخه ${TermsService.currentVersion}) را پذیرفته‌اید' : 'You accepted rules (v${TermsService.currentVersion})')
                    : (isFa ? 'هنوز نسخه جدید قوانین را نپذیرفته‌اید' : 'You have not accepted the latest rules'),
              ),
              trailing: (user?.termsVersion ?? 0) >= TermsService.currentVersion
                  ? null
                  : FilledButton(
                      onPressed: () async {
                        try {
                          final api = ref.read(authenticatedSessionProvider).api;
                          await api.post('/users/me/terms', {'terms_version': TermsService.currentVersion});
                          ref.read(authNotifierProvider.notifier).checkSession();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(isFa ? 'قوانین پذیرفته شد' : 'Rules accepted')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                          }
                        }
                      },
                      child: Text(isFa ? 'پذیرش' : 'Accept'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
