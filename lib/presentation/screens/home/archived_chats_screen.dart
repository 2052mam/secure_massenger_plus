import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/chat_model.dart';
import '../../../data/services/api_service.dart';
import '../../providers/chat_list_provider.dart';
import '../../providers/locale_provider.dart';
import '../../widgets/chat/chat_labels.dart';
import '../../widgets/chat/chat_list_actions.dart';
import '../../widgets/chat/chat_list_tile.dart';
import '../../widgets/chat/pin_code_dialog.dart';
import '../chat/chat_screen.dart';

/// Asks for the four digit PIN when one is set, then opens the archive.
Future<void> openArchivedChats(BuildContext context, WidgetRef ref) async {
  final labels = ChatLabels.of(context);
  final lock = ref.read(archiveLockProvider);
  final state = ref.read(chatListProvider).valueOrNull;
  final needsPin = (state?.hasArchivePin ?? false) && !lock.isUnlocked;

  if (needsPin) {
    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PinCodeDialog(
        title: labels.archiveLocked,
        subtitle: labels.archivePinEnter,
        onSubmit: (pin, _) async {
          try {
            await lock.unlock(pin);
            return null;
          } on ApiException catch (e) {
            return e.message;
          } catch (e) {
            return '$e';
          }
        },
      ),
    );
    if (unlocked != true || !context.mounted) return;
    // The archive list provider caches per lock instance; force a reload.
    ref.invalidate(archivedChatListProvider);
  }

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const ArchivedChatsScreen()),
  );
}

class ArchivedChatsScreen extends ConsumerWidget {
  const ArchivedChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ChatLabels.of(context);
    final isFa = ref.watch(localeProvider).languageCode == 'fa';
    final async = ref.watch(archivedChatListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(labels.archivedChats),
        actions: [
          if (ref.watch(archiveLockProvider).isUnlocked)
            IconButton(
              tooltip: labels.archiveLock,
              icon: const Icon(Icons.lock_outline),
              onPressed: () {
                ref.read(archiveLockProvider).lock();
                ref.invalidate(archivedChatListProvider);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: async.when(
        data: (data) {
          final chats = data.chats;
          if (chats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.archive_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    labels.archiveEmpty,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(archivedChatListProvider.notifier).refresh(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: chats.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 76,
                color: Colors.grey.withValues(alpha: 0.15),
              ),
              itemBuilder: (context, index) {
                final chat = chats[index];
                return ChatListTile(
                  key: ValueKey(chat.id),
                  chat: chat,
                  isFa: isFa,
                  onTap: () => _open(context, chat),
                  onLongPress: () => showChatContextMenu(context, ref, chat),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          final locked = error is ApiException && error.statusCode == 423;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  locked ? Icons.lock_outline : Icons.error_outline,
                  size: 56,
                  color: Colors.grey[500],
                ),
                const SizedBox(height: 12),
                Text(locked ? labels.archiveLocked : '$error'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () =>
                      ref.read(archivedChatListProvider.notifier).refresh(),
                  child: Text(isFa ? 'تلاش مجدد' : 'Retry'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _open(BuildContext context, ChatModel chat) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chat.id,
          title: chat.displayTitle,
          chatType: chat.chatType,
          otherUser: chat.otherUser,
          avatarUrl: chat.avatarUrl,
        ),
      ),
    );
  }
}
