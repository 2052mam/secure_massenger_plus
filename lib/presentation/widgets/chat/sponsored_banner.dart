import 'package:flutter/material.dart';
import '../../../data/models/chat_model.dart';
import '../../screens/chat/chat_screen.dart';

/// Sponsored channels strip (visible to everyone, set by the general admin).
class SponsoredBanner extends StatelessWidget {
  final List<ChatModel> channels;
  const SponsoredBanner({super.key, required this.channels});

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.withValues(alpha: 0.18), Colors.orange.withValues(alpha: 0.10)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.campaign_outlined, size: 18, color: Colors.amber),
            const SizedBox(width: 6),
            Text('کانال‌های اسپانسرشده',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: theme.colorScheme.onSurface)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(8)),
              child: const Text('تبلیغات', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black87)),
            ),
          ]),
          const SizedBox(height: 8),
          ...channels.take(5).map((c) => InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(chatId: c.id, title: c.displayTitle, chatType: c.chatType, avatarUrl: c.avatarUrl),
                  ),
                ),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 18,
                      child: Text((c.title ?? '?').isNotEmpty ? (c.title ?? '?')[0] : '?'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.displayTitle,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          if (c.username?.isNotEmpty == true)
                            Text('@${c.username}',
                                style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_left, color: Colors.grey),
                  ]),
                ),
              )),
        ],
      ),
    );
  }
}
