import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/message_model.dart';
import '../../../data/services/media_download_service.dart';
import 'chat_labels.dart';

class MessageActionsSheet extends StatelessWidget {
  const MessageActionsSheet({
    super.key,
    required this.message,
    required this.canDeleteForAll,
    this.canReply = true,
    this.canPin = false,
    this.canForward = true,
    this.canEdit = false,
    required this.onReply,
    required this.onForward,
    required this.onDelete,
    this.onTogglePin,
    this.onEdit,
  });

  final MessageModel message;
  final bool canDeleteForAll;
  final bool canReply;

  /// Pinning is allowed for private chats and for group/channel members with
  /// the pin right. Several messages can stay pinned at the same time.
  final bool canPin;

  /// False when forwarding is blocked (chat-level or user-level privacy).
  final bool canForward;

  /// True when the current user may edit this message (own text/caption).
  final bool canEdit;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final ValueChanged<bool> onDelete;
  final ValueChanged<bool>? onTogglePin;
  final VoidCallback? onEdit;

  Future<void> _copy(BuildContext context) async {
    final text = message.copyableText;
    if (text == null) return;
    final labels = ChatLabels.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Copy only the exact body/caption, not the author, quote or timestamp.
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(labels.copied)));
    } catch (_) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(labels.copyFailed)));
      }
    }
  }

  Future<void> _download(BuildContext context) async {
    final mediaId = message.mediaId;
    if (mediaId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();

    final ext = message.messageType == 'image' ? 'jpg' :
                message.messageType == 'video' ? 'mp4' :
                message.messageType == 'voice' ? 'm4a' : 'file';
    final fileName = message.originalName ??
        (message.content?.isNotEmpty == true ? message.content! : '${message.messageType}_${message.id}.$ext');
    final mediaUrl = message.mediaUrl ?? '/api/v1/media/$mediaId';

    try {
      messenger.showSnackBar(const SnackBar(content: Text('در حال دانلود فایل...')));
      final path = await MediaDownloadService.downloadMedia(
        mediaUrl: mediaUrl,
        fileName: fileName,
      );
      messenger.showSnackBar(SnackBar(content: Text('فایل ذخیره شد: $fileName')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('خطا در دانلود: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = ChatLabels.of(context);
    void closeAndRun(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canReply)
              ListTile(
                leading: const Icon(Icons.reply),
                title: Text(labels.reply),
                onTap: () => closeAndRun(onReply),
              ),
            if (message.copyableText != null)
              ListTile(
                key: const ValueKey('copy-message'),
                leading: const Icon(Icons.copy_outlined),
                title: Text(labels.copy),
                onTap: () => _copy(context),
              ),
            if (message.mediaId != null && !message.isViewOnce)
              ListTile(
                key: const ValueKey('download-media'),
                leading: const Icon(Icons.download_rounded),
                title: const Text('دانلود / ذخیره در دستگاه'),
                onTap: () => _download(context),
              ),
            if (canPin && onTogglePin != null)
              ListTile(
                key: const ValueKey('pin-message'),
                leading: Icon(
                  message.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                ),
                title: Text(
                  message.isPinned ? labels.unpinMessage : labels.pinMessage,
                ),
                onTap: () =>
                    closeAndRun(() => onTogglePin!(!message.isPinned)),
              ),
            if (canEdit && onEdit != null)
              ListTile(
                key: const ValueKey('edit-message'),
                leading: const Icon(Icons.edit_outlined),
                title: const Text('ویرایش'),
                onTap: () => closeAndRun(onEdit!),
              ),
            if (!message.isViewOnce)
              if (canForward)
                ListTile(
                  leading: const Icon(Icons.forward),
                  title: Text(labels.forward),
                  onTap: () => closeAndRun(onForward),
                )
              else
                const ListTile(
                  leading: Icon(Icons.block_outlined, color: Colors.grey),
                  title: Text('فوروارد غیرفعال است',
                      style: TextStyle(color: Colors.grey)),
                  subtitle: Text('مدیر فوروارد از این گفتگو را بسته است',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  enabled: false,
                ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(labels.deleteForMe),
              onTap: () => closeAndRun(() => onDelete(false)),
            ),
            if (canDeleteForAll)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: Text(
                  labels.deleteForAll,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () => closeAndRun(() => onDelete(true)),
              ),
          ],
        ),
      ),
    );
  }
}
