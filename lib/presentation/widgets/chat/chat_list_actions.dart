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

  // Telegram-style delete: one-way (only for me) vs two-way (for everyone,
  // wiping the whole history). Only private 1:1 chats offer "for everyone".
  var deleteForAll = false;
  if (action == 'delete') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteChatDialog(chat: chat),
    );
    if (confirmed == null || !context.mounted) return;
    deleteForAll = confirmed;
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
        await api.post('/chats/${chat.id}/delete', {'for_all': deleteForAll});
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

/// Delete confirmation with a one-way / two-way choice, like Telegram.
/// Returns `true` when the chat must also be deleted for the other side.
class _DeleteChatDialog extends StatefulWidget {
  final ChatModel chat;
  const _DeleteChatDialog({required this.chat});

  @override
  State<_DeleteChatDialog> createState() => _DeleteChatDialogState();
}

class _DeleteChatDialogState extends State<_DeleteChatDialog> {
  bool _forAll = false;

  @override
  Widget build(BuildContext context) {
    final labels = ChatLabels.of(context);
    // Groups/channels leave instead of deleting; two-way delete is a
    // private-chat concept (the server also enforces this).
    final canDeleteForAll = widget.chat.chatType == 'private';
    return AlertDialog(
      title: Text(labels.delete),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.chat.displayTitle,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            _forAll
                ? 'گفتگو و تمام تاریخچه‌ی آن برای هر دو طرف حذف می‌شود و قابل بازگشت نیست.'
                : 'گفتگو فقط از لیست شما حذف می‌شود. طرف مقابل همچنان به تاریخچه دسترسی دارد.',
            style: const TextStyle(fontSize: 13),
          ),
          if (canDeleteForAll) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'حذف برای طرف مقابل هم',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'تاریخچه‌ی کامل برای هر دو نفر پاک می‌شود',
                style: TextStyle(fontSize: 12),
              ),
              value: _forAll,
              activeColor: Colors.red,
              onChanged: (v) => setState(() => _forAll = v ?? false),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(labels.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, canDeleteForAll && _forAll),
          child: Text(
            _forAll ? 'حذف برای همه' : labels.delete,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}
