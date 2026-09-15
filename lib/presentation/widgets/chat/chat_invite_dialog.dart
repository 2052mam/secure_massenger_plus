import 'package:flutter/material.dart';

import '../../../data/models/chat_invite_model.dart';
import 'chat_avatar.dart';
import 'chat_labels.dart';

/// Like Telegram, a private group's details are previewed before joining.
class ChatInviteDialog extends StatelessWidget {
  const ChatInviteDialog({super.key, required this.invite, this.token});

  final ChatInviteModel invite;
  final String? token;

  @override
  Widget build(BuildContext context) {
    final labels = ChatLabels.of(context);
    return AlertDialog(
      title: Text(labels.invite),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChatAvatar(
              title: invite.title,
              url: invite.avatarUrl,
              token: token,
              radius: 32,
            ),
            const SizedBox(height: 12),
            Text(
              invite.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              labels.members(
                invite.membersCount,
                subscribers: invite.chatType == 'channel',
              ),
            ),
            if (invite.description?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(invite.description!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(labels.cancel),
        ),
        FilledButton(
          key: const ValueKey('join-invite'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            invite.chatType == 'channel'
                ? labels.joinChannel
                : labels.joinGroup,
          ),
        ),
      ],
    );
  }
}
