import 'package:flutter/material.dart';

import '../../../core/utils/chat_list_time.dart';
import '../../../data/models/chat_model.dart';
import '../../../data/services/storage_service.dart';
import 'chat_avatar.dart';

/// One row of the chat list (also used by the archive screen).
class ChatListTile extends StatelessWidget {
  const ChatListTile({
    super.key,
    required this.chat,
    required this.isFa,
    required this.onTap,
    this.onLongPress,
  });

  final ChatModel chat;
  final bool isFa;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = chat.lastMessage;
    String subtitle = '';
    if (last != null) {
      if (last.messageType == 'image') {
        subtitle = isFa ? '📷 عکس' : '📷 Photo';
      } else if (last.messageType == 'video') {
        subtitle = isFa ? '🎥 ویدیو' : '🎥 Video';
      } else if (last.messageType == 'voice') {
        subtitle = isFa ? '🎤 پیام صوتی' : '🎤 Voice message';
      } else {
        subtitle = last.content ?? '';
      }
    }

    final timeStr = last?.createdAt == null
        ? ''
        : formatChatListTime(last!.createdAt!, locale: isFa ? 'fa' : 'en');

    final isOnline =
        chat.otherUser?.isOnline == true &&
        (chat.otherUser?.showLastSeen ?? true);
    final avatarUrl = chat.chatType == 'private'
        ? (chat.otherUser?.showProfilePhoto == true
              ? chat.otherUser?.avatarUrl
              : null)
        : chat.avatarUrl;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                children: [
                  ChatAvatar(
                    title: chat.displayTitle,
                    url: avatarUrl,
                    token: StorageService.getToken(),
                    radius: 28,
                  ),
                  if (chat.chatType == 'private' && isOnline)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (chat.chatType == 'channel')
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 4),
                            child: Icon(
                              Icons.campaign_outlined,
                              size: 15,
                              color: Colors.grey[500],
                            ),
                          )
                        else if (chat.chatType == 'group')
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 4),
                            child: Icon(
                              Icons.group_outlined,
                              size: 15,
                              color: Colors.grey[500],
                            ),
                          ),
                        Expanded(
                          child: Text(
                            chat.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: chat.unreadCount > 0
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (chat.isMuted)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 4),
                            child: Icon(
                              Icons.volume_off_rounded,
                              size: 15,
                              color: Colors.grey[500],
                            ),
                          ),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: chat.unreadCount > 0
                                ? theme.colorScheme.primary
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                              fontWeight: chat.unreadCount > 0
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (chat.isPinned && chat.unreadCount == 0)
                          Icon(
                            Icons.push_pin_rounded,
                            size: 15,
                            color: Colors.grey[500],
                          ),
                        if (chat.unreadCount > 0)
                          Container(
                            margin: const EdgeInsetsDirectional.only(start: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: chat.isMuted
                                  ? Colors.grey
                                  : theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              chat.unreadCount > 99
                                  ? '99+'
                                  : '${chat.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
