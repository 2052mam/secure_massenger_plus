import 'package:flutter/material.dart';
import '../../../core/utils/media_utils.dart';
import '../../../data/services/music_player_service.dart';
import '../../screens/music/music_player_screen.dart';

/// Telegram-like collapsed mini player shown above the bottom navigation
/// and at the bottom of chat screens while music plays.
class MiniMusicPlayer extends StatelessWidget {
  const MiniMusicPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MusicPlayerState>(
      stream: MusicPlayerService().stream,
      initialData: MusicPlayerService().state,
      builder: (context, snap) {
        final st = snap.data ?? MusicPlayerService().state;
        final track = st.current;
        if (track == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final progress = st.duration.inMilliseconds > 0
            ? (st.position.inMilliseconds / st.duration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MusicPlayerScreen()),
          ),
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        ),
                        child: Icon(Icons.music_note_rounded, color: theme.colorScheme.primary, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(track.title,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(
                              track.artist.isNotEmpty
                                  ? '${track.artist} • ${formatMediaDuration(st.position)} / ${formatMediaDuration(st.duration)}'
                                  : '${formatMediaDuration(st.position)} / ${formatMediaDuration(st.duration)}',
                              style: const TextStyle(color: Colors.grey, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(st.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        color: theme.colorScheme.primary,
                        onPressed: () => MusicPlayerService().toggle(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: st.queue.length > 1 ? () => MusicPlayerService().next() : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => MusicPlayerService().close(),
                      ),
                    ],
                  ),
                ),
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: Colors.grey.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
