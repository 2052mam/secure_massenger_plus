import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/api_service.dart';
import '../../providers/chat_list_provider.dart';
import '../../widgets/chat/chat_labels.dart';
import '../../widgets/chat/pin_code_dialog.dart';

/// Settings section for the four digit archive password (Telegram keeps the
/// archive behind a lock in the same way).
class ArchiveLockScreen extends ConsumerWidget {
  const ArchiveLockScreen({super.key});

  Future<void> _setPin(
    BuildContext context,
    WidgetRef ref, {
    required bool change,
  }) async {
    final labels = ChatLabels.of(context);
    final lock = ref.read(archiveLockProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => PinCodeDialog(
        title: change ? labels.archivePinChange : labels.archivePinCreate,
        subtitle: labels.archiveLockHint,
        confirmLabel: labels.save,
        requireRepeat: true,
        requireCurrent: change,
        onSubmit: (pin, currentPin) async {
          try {
            await lock.setPin(pin, currentPin: currentPin);
            return null;
          } on ApiException catch (e) {
            return e.message;
          } catch (e) {
            return '$e';
          }
        },
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(chatListProvider.notifier).refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(labels.archivePinSet)));
  }

  Future<void> _removePin(BuildContext context, WidgetRef ref) async {
    final labels = ChatLabels.of(context);
    final lock = ref.read(archiveLockProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => PinCodeDialog(
        title: labels.archivePinRemove,
        subtitle: labels.archivePinEnter,
        confirmLabel: labels.delete,
        onSubmit: (pin, _) async {
          try {
            await lock.removePin(pin);
            return null;
          } on ApiException catch (e) {
            return e.message;
          } catch (e) {
            return '$e';
          }
        },
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(chatListProvider.notifier).refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(labels.archivePinRemoved)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ChatLabels.of(context);
    final state = ref.watch(chatListProvider).valueOrNull;
    final hasPin = state?.hasArchivePin ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(labels.archiveLock)),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                labels.archiveLockHint,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            ListTile(
              key: const ValueKey('archive-pin-status'),
              leading: Icon(hasPin ? Icons.lock : Icons.lock_open_outlined),
              title: Text(labels.archivePinTitle),
              subtitle: Text(
                hasPin ? labels.archivePinOn : labels.archivePinOff,
              ),
              trailing: TextButton(
                onPressed: () => _setPin(context, ref, change: hasPin),
                child: Text(
                  hasPin ? labels.archivePinChange : labels.archivePinCreate,
                ),
              ),
            ),
            if (hasPin)
              ListTile(
                key: const ValueKey('archive-pin-remove'),
                leading: const Icon(Icons.lock_open, color: Colors.red),
                title: Text(
                  labels.archivePinRemove,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () => _removePin(context, ref),
              ),
            if (hasPin && ref.watch(archiveLockProvider).isUnlocked)
              ListTile(
                leading: const Icon(Icons.lock_clock_outlined),
                title: Text(labels.archiveLocked),
                subtitle: Text(labels.archiveLockHint),
                trailing: TextButton(
                  onPressed: () {
                    ref.read(archiveLockProvider).lock();
                    ref.invalidate(archivedChatListProvider);
                  },
                  child: Text(labels.archiveLock),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
