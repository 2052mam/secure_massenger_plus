import 'package:flutter/material.dart';

import '../../../data/models/message_model.dart';
import '../../widgets/chat/chat_labels.dart';
import '../../widgets/chat/pinned_messages_bar.dart';

/// Full list of the pinned messages of a chat. Popping returns the id of the
/// message to jump to, or null when nothing was chosen.
class PinnedMessagesScreen extends StatelessWidget {
  const PinnedMessagesScreen({
    super.key,
    required this.pinned,
    this.canPin = false,
    this.onUnpin,
    this.onUnpinAll,
  });

  final List<MessageModel> pinned;
  final bool canPin;
  final ValueChanged<MessageModel>? onUnpin;
  final VoidCallback? onUnpinAll;

  @override
  Widget build(BuildContext context) {
    final labels = ChatLabels.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(labels.pinnedCount(pinned.length)),
        actions: [
          if (canPin && pinned.isNotEmpty && onUnpinAll != null)
            TextButton(
              onPressed: () {
                onUnpinAll!();
                Navigator.of(context).pop();
              },
              child: Text(labels.unpinAll),
            ),
        ],
      ),
      body: pinned.isEmpty
          ? Center(
              child: Text(
                labels.noPinnedMessages,
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
          : ListView.separated(
              itemCount: pinned.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final message = pinned[index];
                return ListTile(
                  key: ValueKey('pinned-${message.id}'),
                  leading: const Icon(Icons.push_pin_outlined),
                  title: Text(
                    message.sender?.displayName ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    messagePreviewText(context, message),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: canPin && onUnpin != null
                      ? IconButton(
                          tooltip: labels.unpinMessage,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            onUnpin!(message);
                            Navigator.of(context).pop();
                          },
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(message.id),
                );
              },
            ),
    );
  }
}
