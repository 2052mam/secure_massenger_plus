import 'package:flutter/material.dart';

import '../../../data/models/message_model.dart';
import 'chat_labels.dart';

String messagePreviewText(BuildContext context, MessageModel message) {
  final labels = ChatLabels.of(context);
  final text = message.content?.trim();
  if (text != null && text.isNotEmpty) return text;
  switch (message.messageType) {
    case 'image':
      return labels.isFa ? '📷 عکس' : '📷 Photo';
    case 'video':
      return labels.isFa ? '🎥 ویدیو' : '🎥 Video';
    case 'voice':
      return labels.isFa ? '🎤 پیام صوتی' : '🎤 Voice message';
    case 'file':
      return labels.isFa ? '📎 فایل' : '📎 File';
  }
  return '';
}

/// Telegram style strip under the app bar. Tapping it jumps to the pinned
/// message; with several pins each tap moves to the next one.
class PinnedMessagesBar extends StatelessWidget {
  const PinnedMessagesBar({
    super.key,
    required this.pinned,
    required this.index,
    required this.onTap,
    required this.onShowAll,
    this.onUnpin,
  });

  final List<MessageModel> pinned;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onShowAll;
  final VoidCallback? onUnpin;

  @override
  Widget build(BuildContext context) {
    if (pinned.isEmpty) return const SizedBox.shrink();
    final labels = ChatLabels.of(context);
    final theme = Theme.of(context);
    final safeIndex = index < 0 || index >= pinned.length ? 0 : index;
    final message = pinned[safeIndex];

    return Material(
      color: theme.colorScheme.surface,
      child: InkWell(
        key: const ValueKey('pinned-bar'),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
            ),
          ),
          padding: const EdgeInsetsDirectional.only(
            start: 12,
            end: 4,
            top: 6,
            bottom: 6,
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pinned.length == 1
                          ? labels.pinnedMessages
                          : '${labels.pinnedMessages} '
                                '${safeIndex + 1}/${pinned.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      messagePreviewText(context, message),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('pinned-bar-list'),
                tooltip: labels.pinnedMessages,
                icon: const Icon(Icons.format_list_bulleted_rounded, size: 20),
                onPressed: onShowAll,
              ),
              if (onUnpin != null)
                IconButton(
                  key: const ValueKey('pinned-bar-unpin'),
                  tooltip: labels.unpinMessage,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onUnpin,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
