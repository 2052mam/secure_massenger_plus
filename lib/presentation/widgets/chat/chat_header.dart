import 'package:flutter/material.dart';

import '../../../data/models/user_model.dart';
import 'chat_avatar.dart';
import 'chat_labels.dart';

class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.title,
    required this.chatType,
    this.otherUser,
    this.avatarUrl,
    this.membersCount,
    this.onlineCount,
    this.token,
    this.onTap,
  });

  final String title;
  final String chatType;
  final UserModel? otherUser;
  final String? avatarUrl;
  final int? membersCount;
  final int? onlineCount;
  final String? token;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final labels = ChatLabels.of(context);
    final peer = otherUser;
    final isPrivate = chatType == 'private' || chatType == 'support';
    final name = isPrivate ? peer?.displayName ?? title : title;
    final photo = isPrivate && peer != null
        ? (peer.showProfilePhoto ? peer.avatarUrl : null)
        : avatarUrl;
    final online =
        isPrivate && peer?.isOnline == true && peer?.showLastSeen == true;
    final String subtitle;
    if (isPrivate && peer != null) {
      subtitle = online
          ? labels.online
          : !peer.showLastSeen || peer.lastSeen == null
          ? labels.lastSeenHidden
          : labels.lastSeen(peer.lastSeen!);
    } else if (chatType == 'group' || chatType == 'channel') {
      if (membersCount == null) {
        subtitle = (chatType == 'channel' ? labels.channel : labels.group);
      } else {
        // Telegram-like: show online count if available
        final base = labels.members(membersCount!, subscribers: chatType == 'channel');
        if (onlineCount != null && onlineCount! > 0 && chatType == 'group') {
          subtitle = '$base، $onlineCount آنلاین';
        } else if (onlineCount != null && onlineCount! > 0 && chatType == 'channel') {
          subtitle = base;
        } else {
          subtitle = base;
        }
      }
    } else if (chatType == 'saved') {
      subtitle = labels.saved;
    } else {
      subtitle = labels.profile;
    }
    final color =
        Theme.of(context).appBarTheme.foregroundColor ??
        Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: onTap != null,
      child: InkWell(
        key: const ValueKey('chat-header'),
        onTap: onTap,
        child: Row(
          children: [
            ChatAvatar(
              title: name,
              url: photo,
              token: token,
              foreground: color,
              fallbackIcon: chatType == 'saved' ? Icons.bookmark : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: color.withValues(alpha: online ? 1 : 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
