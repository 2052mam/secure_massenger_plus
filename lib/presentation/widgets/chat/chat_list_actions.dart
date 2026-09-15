import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/chat_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_list_provider.dart';
import 'chat_labels.dart';

/// Long press menu of a chat row: pin, archive, mute and delete — the same
/// set Telegram offers on the chat list.
Future<void> showChatContextMenu(
  BuildContext context,
  WidgetRef ref,
  ChatModel chat,
) async {
  final labels = ChatLabels.of(context);
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            dense: true,
            title: Text(
              chat.displayTitle,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('chat-menu-pin'),
            leading: Icon(
              chat.isPinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin_rounded,
            ),
            title: Text(chat.isPinned ? labels.unpinChat : labels.pinChat),
            onTap: () => Navigator.pop(ctx, chat.isPinned ? 'unpin' : 'pin'),
          ),
          ListTile(
            key: const ValueKey('chat-menu-archive'),
            leading: Icon(
              chat.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
            ),
            title: Text(
              chat.isArchived ? labels.unarchiveChat : labels.archiveChat,
            ),
            onTap: () =>
                Navigator.pop(ctx, chat.isArchived ? 'unarchive' : 'archive'),
          ),
          ListTile(
            leading: Icon(
              chat.isMuted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
            title: Text(chat.isMuted ? labels.unmute : labels.mute),
            onTap: () => Navigator.pop(ctx, chat.isMuted ? 'unmute' : 'mute'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text(
              labels.delete,
              style: const TextStyle(color: Colors.red),
            ),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  if (action == 'delete') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.delete),
        content: Text(chat.displayTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(labels.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              labels.delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
  }

  final api = ref.read(authenticatedSessionProvider).api;
  try {
    switch (action) {
      case 'pin':
        await api.post('/chats/${chat.id}/pin', {'is_pinned': true});
        break;
      case 'unpin':
        await api.post('/chats/${chat.id}/unpin', {});
        break;
      case 'archive':
        await api.post('/chats/${chat.id}/archive', {'is_archived': true});
        break;
      case 'unarchive':
        await api.post('/chats/${chat.id}/archive', {'is_archived': false});
        break;
      case 'mute':
        await api.post('/chats/${chat.id}/mute', {'is_muted': true});
        break;
      case 'unmute':
        await api.post('/chats/${chat.id}/mute', {'is_muted': false});
        break;
      case 'delete':
        await api.post('/chats/${chat.id}/delete', {'for_all': false});
        break;
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
  await ref.read(chatListProvider.notifier).refresh();
  await ref.read(archivedChatListProvider.notifier).refresh();
}
