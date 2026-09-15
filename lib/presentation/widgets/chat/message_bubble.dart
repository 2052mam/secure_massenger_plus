import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/chat_invite_link.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/reply_preview_model.dart';
import '../../../data/services/media_playback_coordinator.dart';
import '../media/media_labels.dart';
import '../media/video_message_player.dart';
import '../media/video_note_player.dart';
import '../media/voice_message_player.dart';
import '../music/music_message_bubble.dart';
import 'encrypted_bubble.dart';
import 'location_bubble.dart';
import 'reaction_bar.dart';
import 'reply_preview.dart';
import 'message_text.dart';
import 'spoiler_widget.dart';
import 'file_message_bubble.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final String mediaUrl;
  final String? token;
  final String? currentUserId;
  final ReplyPreviewModel? reply;
  final VoidCallback? onReplyTap;
  final VoidCallback? onOpenPhoto;
  final VoidCallback? onOpenViewOnce;
  final ValueChanged<ChatInviteLink>? onInviteTap;
  final MediaPlaybackCoordinator? coordinator;
  final bool highlighted;
  final bool showSender;
  final ValueChanged<String>? onReactionTap;
  final VoidCallback? onAddReaction;
  final ValueChanged<String>? onMentionTap;
  final List<MessageModel> musicQueue;
  final String chatTitle;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.mediaUrl,
    this.token,
    this.currentUserId,
    this.reply,
    this.onReplyTap,
    this.onOpenPhoto,
    this.onOpenViewOnce,
    this.onInviteTap,
    this.coordinator,
    this.highlighted = false,
    this.showSender = false,
    this.onReactionTap,
    this.onAddReaction,
    this.onMentionTap,
    this.musicQueue = const [],
    this.chatTitle = '',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = MediaLabels.of(context);
    final bg = isMine ? theme.colorScheme.primary : theme.cardColor;
    final fg = isMine ? Colors.white : theme.colorScheme.onSurface;
    final quote = reply ?? message.replyTo;
    final rendersMedia =
        ((message.messageType == 'image' || message.messageType == 'video') &&
            mediaUrl.isNotEmpty) ||
        message.messageType == 'voice' ||
        message.messageType == 'audio';
    final hasCaption =
        !message.isViewOnce &&
        rendersMedia &&
        message.content?.trim().isNotEmpty == true;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(
            color: highlighted ? Colors.amber : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (showSender && !isMine && (message.author != null || message.sender != null))
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Publishing admin name (channel signature / group author).
                    Flexible(
                      child: Text(
                        message.author?.displayName ?? message.sender!.displayName,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (message.author?.username?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          '@${message.author!.username}',
                          style: TextStyle(
                            color: theme.colorScheme.primary.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    if (message.author != null)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'مدیر',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (message.replyToId != null || quote != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: ReplyPreview(
                  reply:
                      quote ??
                      ReplyPreviewModel.unavailable(message.replyToId!),
                  currentUserId: currentUserId,
                  token: token,
                  foreground: isMine ? Colors.white : theme.colorScheme.primary,
                  onTap: onReplyTap,
                ),
              ),
            if (message.isEncrypted)
              EncryptedBubble(
                message: message,
                isMine: isMine,
                foreground: fg,
                onInviteTap: onInviteTap,
                onMentionTap: onMentionTap,
                onOpenPhoto: onOpenPhoto,
              )
            else if (message.isLocation)
              LocationBubble(message: message, isMine: isMine)
            else if (message.isViewOnce)
              _ViewOnceTile(
                viewed: message.viewedAt != null,
                isMine: isMine,
                color: fg,
                onTap: !isMine && message.viewedAt == null
                    ? onOpenViewOnce
                    : null,
              )
            else if (message.messageType == 'image' && mediaUrl.isNotEmpty)
              SpoilerWidget(
                isSpoiler: message.isSpoiler,
                child: Semantics(
                  button: true,
                  label: labels.photo,
                  child: GestureDetector(
                    onTap: onOpenPhoto,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: CachedNetworkImage(
                          imageUrl: mediaUrl,
                          httpHeaders: token == null
                              ? null
                              : {'Authorization': 'Bearer $token'},
                          width: 280,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const SizedBox(
                            width: 280,
                            height: 180,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, __, ___) => SizedBox(
                            width: 220,
                            height: 100,
                            child: Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 40,
                                color: fg,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else if (message.messageType == 'video' && mediaUrl.isNotEmpty)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.isMuted)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.volume_off, size: 12, color: Colors.white),
                          SizedBox(width: 4),
                          Text('بی‌صدا', style: TextStyle(color: Colors.white, fontSize: 10)),
                        ],
                      ),
                    ),
                  SpoilerWidget(
                    isSpoiler: message.isSpoiler,
                    child: VideoMessagePlayer(
                      url: mediaUrl,
                      authToken: token,
                      isMine: isMine,
                      coordinator: coordinator,
                      muted: message.isMuted,
                    ),
                  ),
                ],
              )
            else if (message.messageType == 'video_note' || message.messageType == 'round_video')
              mediaUrl.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: VideoNotePlayer(url: mediaUrl, authToken: token, size: 180),
                    )
                  : SpoilerWidget(
                      isSpoiler: message.isSpoiler,
                      child: MessageText(
                        text: 'ویدیو مسیج ${message.content ?? ''}'.trim(),
                        style: TextStyle(color: fg, fontSize: 14),
                        linkColor: isMine ? Colors.white : theme.colorScheme.primary,
                        onInviteTap: onInviteTap,
                        onMentionTap: onMentionTap,
                      ),
                    )
            else if (message.messageType == 'sticker')
              mediaUrl.isNotEmpty
                  ? GestureDetector(
                      onTap: onOpenPhoto,
                      child: CachedNetworkImage(
                        imageUrl: mediaUrl,
                        httpHeaders: token == null ? null : {'Authorization': 'Bearer $token'},
                        width: 140,
                        height: 140,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const SizedBox(width: 80, height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                        errorWidget: (_, __, ___) => Text(message.content ?? 'استیکر', style: TextStyle(fontSize: 48)),
                      ),
                    )
                  : Text(message.content ?? 'استیکر', style: TextStyle(fontSize: 48, color: fg))
            else if (message.messageType == 'gif')
              mediaUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          CachedNetworkImage(
                            imageUrl: mediaUrl,
                            httpHeaders: token == null ? null : {'Authorization': 'Bearer $token'},
                            width: 220,
                            height: 160,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(width: 220, height: 160, color: Colors.black12, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                            errorWidget: (_, __, ___) => Container(width: 220, height: 120, color: Colors.black12, child: Icon(Icons.gif_box, color: fg, size: 32)),
                          ),
                          Positioned(
                            bottom: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                              child: const Text('GIF', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : MessageText(
                      text: message.content ?? 'GIF',
                      style: TextStyle(color: fg),
                      linkColor: isMine ? Colors.white : theme.colorScheme.primary,
                      onInviteTap: onInviteTap,
                      onMentionTap: onMentionTap,
                    )
            else if (message.messageType == 'voice')
              VoiceMessagePlayer(
                url: mediaUrl,
                token: token,
                foreground: fg,
                coordinator: coordinator,
              )
            else if (message.isMusic)
              MusicMessageBubble(
                message: message,
                isMine: isMine,
                foreground: fg,
                queue: musicQueue.isEmpty ? [message] : musicQueue,
                chatTitle: chatTitle,
                token: token,
              )
            else if (message.messageType == 'file')
              FileMessageBubble(
                message: message,
                mediaUrl: mediaUrl,
                token: token,
                isMine: isMine,
                foregroundColor: fg,
              )
            else
              SpoilerWidget(
                isSpoiler: message.isSpoiler,
                child: MessageText(
                  text: message.content?.isNotEmpty == true
                      ? message.content!
                      : labels.type(message.messageType),
                  style: TextStyle(color: fg, fontSize: 15, height: 1.35),
                  linkColor: isMine ? Colors.white : theme.colorScheme.primary,
                  onInviteTap: onInviteTap,
                  onMentionTap: onMentionTap,
                ),
              ),
            if (hasCaption)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: MessageText(
                  text: message.content!,
                  style: TextStyle(color: fg),
                  linkColor: isMine ? Colors.white : theme.colorScheme.primary,
                  onInviteTap: onInviteTap,
                  onMentionTap: onMentionTap,
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              widthFactor: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.forwardedFromId != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forward, size: 11, color: fg.withValues(alpha: 0.65)),
                          const SizedBox(width: 2),
                          Text(
                            'فوروارد شده',
                            style: TextStyle(color: fg.withValues(alpha: 0.65), fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  if (message.isEdited)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'ویرایش شده',
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.65),
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  Text(
                    '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.65),
                      fontSize: 11,
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.status == 'sent' ? Icons.done : Icons.done_all,
                      size: 16,
                      color: message.status == 'read'
                          ? const Color(0xFF4FC3F7)
                          : Colors.white70,
                    ),
                  ],
                ],
              ),
            ),
            if (message.reactions.isNotEmpty)
              ReactionBar(
                reactions: message.reactions,
                onReactionTap: onReactionTap,
                onAddReaction: onAddReaction,
              ),
          ],
        ),
      ),
    );
  }
}

class _ViewOnceTile extends StatelessWidget {
  final bool viewed;
  final bool isMine;
  final Color color;
  final VoidCallback? onTap;

  const _ViewOnceTile({
    required this.viewed,
    required this.isMine,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labels = MediaLabels.of(context);
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                viewed ? Icons.timer_off_outlined : Icons.timer_outlined,
                color: color,
                size: 30,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      viewed ? labels.viewed : labels.viewOnce,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (!viewed) ...[
                      const SizedBox(height: 3),
                      Text(
                        isMine ? labels.sentOnce : labels.tapToOpen,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.75),
                          fontSize: 12,
                        ),
                      ),
                    ],
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
