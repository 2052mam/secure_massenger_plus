import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/media_utils.dart';
import '../../../data/models/reply_preview_model.dart';
import '../media/media_labels.dart';

class ReplyPreview extends StatelessWidget {
  final ReplyPreviewModel reply;
  final String? currentUserId;
  final String? token;
  final Color? foreground;
  final VoidCallback? onTap;

  const ReplyPreview({
    super.key,
    required this.reply,
    this.currentUserId,
    this.token,
    this.foreground,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labels = MediaLabels.of(context);
    final color = foreground ?? Theme.of(context).colorScheme.primary;
    final sender = reply.isUnavailable
        ? labels.reply
        : reply.senderId == currentUserId
        ? labels.you
        : (reply.senderName?.isNotEmpty == true
              ? reply.senderName!
              : labels.unknownSender);
    final caption = reply.content?.trim() ?? '';
    final snippet = reply.isUnavailable
        ? labels.unavailable
        : reply.isViewOnce
        ? labels.viewOnce
        : reply.messageType == 'text' && caption.isNotEmpty
        ? caption
        : '${labels.type(reply.messageType)}${caption.isEmpty ? '' : ' · $caption'}';
    final canTap = !reply.isUnavailable && onTap != null;

    return Semantics(
      button: canTap,
      label: '${labels.reply} $sender: $snippet',
      child: Material(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canTap ? onTap : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsetsDirectional.fromSTEB(9, 7, 8, 7),
            decoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: color, width: 3),
              ),
            ),
            child: Row(
              children: [
                if (!reply.isViewOnce &&
                    !reply.isUnavailable &&
                    reply.mediaUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: resolveMediaUrl(
                        null,
                        existingUrl: reply.mediaUrl,
                      ),
                      httpHeaders: token == null
                          ? null
                          : {'Authorization': 'Bearer $token'},
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          Icon(Icons.image_outlined, color: color),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sender,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
