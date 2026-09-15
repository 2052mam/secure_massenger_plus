import 'package:flutter/material.dart';
import '../../../core/utils/media_utils.dart';
import '../../../data/models/message_model.dart';
import '../../../data/services/music_player_service.dart';

/// Telegram-like music/audio bubble: artwork icon, title/artist, play button,
/// duration. Tapping play enqueues the whole chat's music queue.
class MusicMessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final Color foreground;
  final List<MessageModel> queue;
  final String chatTitle;
  final String? token;

  const MusicMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.foreground,
    this.queue = const [],
    this.chatTitle = '',
    this.token,
  });

  String get _title {
    if (message.audioTitle?.isNotEmpty == true) return message.audioTitle!;
    if (message.originalName?.isNotEmpty == true) {
      return message.originalName!.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
    }
    return 'Audio';
  }

  String get _artist {
    if (message.audioArtist?.isNotEmpty == true) return message.audioArtist!;
    return message.sender?.displayName ?? chatTitle;
  }

  String get _duration {
    final d = message.audioDuration;
    if (d == null || d <= 0) return '';
    return formatMediaDuration(Duration(seconds: d.round()));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MusicPlayerState>(
      stream: MusicPlayerService().stream,
      initialData: MusicPlayerService().state,
      builder: (context, snap) {
        final st = snap.data ?? MusicPlayerService().state;
        final isCurrent = st.current?.message.id == message.id;
        final playing = isCurrent && st.playing;
        return GestureDetector(
          onTap: () {
            final tracks = (queue.isEmpty ? [message] : queue)
                .map((m) => MusicTrack(message: m, chatTitle: chatTitle))
                .toList();
            var idx = tracks.indexWhere((t) => t.message.id == message.id);
            if (idx < 0) idx = 0;
            if (isCurrent) {
              MusicPlayerService().toggle();
            } else {
              MusicPlayerService().playQueue(tracks, startIndex: idx, token: token);
            }
          },
          child: Container(
            width: 230,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isMine ? Colors.white.withValues(alpha: 0.25) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  ),
                  child: isCurrent && st.loading
                      ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: isMine ? Colors.white : Theme.of(context).colorScheme.primary,
                          size: 28,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_title,
                          style: TextStyle(color: foreground, fontWeight: FontWeight.w600, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(_artist,
                          style: TextStyle(color: foreground.withValues(alpha: 0.7), fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (isCurrent && st.duration.inSeconds > 0) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: st.duration.inMilliseconds > 0
                                ? (st.position.inMilliseconds / st.duration.inMilliseconds).clamp(0.0, 1.0)
                                : 0,
                            minHeight: 3,
                            backgroundColor: foreground.withValues(alpha: 0.15),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${formatMediaDuration(st.position)} / ${formatMediaDuration(st.duration)}',
                          style: TextStyle(color: foreground.withValues(alpha: 0.6), fontSize: 10),
                          textDirection: TextDirection.ltr,
                        ),
                      ] else if (_duration.isNotEmpty)
                        Text(_duration,
                            style: TextStyle(color: foreground.withValues(alpha: 0.6), fontSize: 11),
                            textDirection: TextDirection.ltr),
                    ],
                  ),
                ),
                const Icon(Icons.music_note_rounded, size: 18, color: Colors.grey),
              ],
            ),
          ),
        );
      },
    );
  }
}
