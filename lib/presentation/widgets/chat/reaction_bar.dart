import 'package:flutter/material.dart';
import '../../../data/models/reaction_model.dart';

class ReactionBar extends StatelessWidget {
  final List<ReactionModel> reactions;
  final ValueChanged<String>? onReactionTap;
  final VoidCallback? onAddReaction;

  const ReactionBar({
    super.key,
    required this.reactions,
    this.onReactionTap,
    this.onAddReaction,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          ...reactions.map((r) => GestureDetector(
                onTap: () => onReactionTap?.call(r.emoji),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: r.me ? Colors.blue.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: r.me ? Colors.blue.withValues(alpha: 0.5) : Colors.transparent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(r.emoji, style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 3),
                      Text('${r.count}', style: TextStyle(fontSize: 11, color: r.me ? Colors.blue : Colors.black54, fontWeight: r.me ? FontWeight.w600 : FontWeight.normal)),
                    ],
                  ),
                ),
              )),
          if (onAddReaction != null)
            GestureDetector(
              onTap: onAddReaction,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add_reaction_outlined, size: 16, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}

class QuickReactionSheet extends StatelessWidget {
  const QuickReactionSheet({super.key});

  static const quickEmojis = ['❤️', '👍', '🔥', '😂', '😮', '😢', '🙏', '👏', '🎉', '🤔', '🥰', '😍'];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            ...quickEmojis.map((e) => InkWell(
                  onTap: () => Navigator.pop(context, e),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 28)),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
