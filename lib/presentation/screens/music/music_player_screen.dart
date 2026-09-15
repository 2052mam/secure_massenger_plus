import 'package:flutter/material.dart';
import '../../../core/utils/media_utils.dart';
import '../../../data/services/music_player_service.dart';

/// Telegram-like full music player: artwork, title/artist, seek bar,
/// play/pause/next/prev, speed, repeat, shuffle, queue list.
class MusicPlayerScreen extends StatelessWidget {
  const MusicPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('پخش‌کننده موسیقی'),
        actions: [
          StreamBuilder<MusicPlayerState>(
            stream: MusicPlayerService().stream,
            initialData: MusicPlayerService().state,
            builder: (context, snap) {
              final st = snap.data ?? MusicPlayerService().state;
              return IconButton(
                tooltip: 'بستن پخش',
                icon: const Icon(Icons.close_rounded),
                onPressed: () async {
                  await MusicPlayerService().close();
                  if (context.mounted) Navigator.pop(context);
                },
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<MusicPlayerState>(
          stream: MusicPlayerService().stream,
          initialData: MusicPlayerService().state,
          builder: (context, snap) {
            final st = snap.data ?? MusicPlayerService().state;
            final track = st.current;
            if (track == null) {
              return const Center(child: Text('چیزی در حال پخش نیست'));
            }
            final progress = st.duration.inMilliseconds > 0
                ? st.position.inMilliseconds / st.duration.inMilliseconds
                : 0.0;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [theme.colorScheme.primary.withValues(alpha: 0.25), theme.cardColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(child: Icon(Icons.music_note_rounded, size: 96, color: Colors.grey)),
                ),
                const SizedBox(height: 20),
                Text(track.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text(track.artist,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 20),
                Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: (v) {
                    final ms = (v * st.duration.inMilliseconds).round();
                    MusicPlayerService().seek(Duration(milliseconds: ms));
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatMediaDuration(st.position), style: const TextStyle(fontSize: 12, color: Colors.grey), textDirection: TextDirection.ltr),
                      Text(formatMediaDuration(st.duration), style: const TextStyle(fontSize: 12, color: Colors.grey), textDirection: TextDirection.ltr),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'تکرار',
                      icon: Icon(
                        st.repeatMode == 2 ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                        color: st.repeatMode == 0 ? Colors.grey : theme.colorScheme.primary,
                      ),
                      onPressed: () => MusicPlayerService().cycleRepeat(),
                    ),
                    IconButton(
                      tooltip: '۱۰ ثانیه عقب',
                      icon: const Icon(Icons.replay_10_rounded, size: 30),
                      onPressed: () => MusicPlayerService().seekBackward(),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primary),
                      child: IconButton(
                        iconSize: 40,
                        color: Colors.white,
                        icon: st.loading
                            ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                            : Icon(st.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        onPressed: () => MusicPlayerService().toggle(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: '۱۰ ثانیه جلو',
                      icon: const Icon(Icons.forward_10_rounded, size: 30),
                      onPressed: () => MusicPlayerService().seekForward(),
                    ),
                    IconButton(
                      tooltip: 'تصادفی',
                      icon: Icon(Icons.shuffle_rounded,
                          color: st.shuffle ? theme.colorScheme.primary : Colors.grey),
                      onPressed: () => MusicPlayerService().toggleShuffle(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'قبلی',
                      icon: const Icon(Icons.skip_previous_rounded, size: 32),
                      onPressed: st.queue.length > 1 ? () => MusicPlayerService().previous() : null,
                    ),
                    const SizedBox(width: 16),
                    FilledButton.tonal(
                      onPressed: () => MusicPlayerService().cycleSpeed(),
                      child: Text('${st.speed}x'),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      tooltip: 'بعدی',
                      icon: const Icon(Icons.skip_next_rounded, size: 32),
                      onPressed: st.queue.length > 1 ? () => MusicPlayerService().next() : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                Row(
                  children: [
                    const Icon(Icons.queue_music_rounded, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('صف پخش (${st.queue.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(st.queue.length, (i) {
                  final t = st.queue[i];
                  final selected = i == st.index;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      selected ? Icons.play_circle_filled_rounded : Icons.music_note_rounded,
                      color: selected ? theme.colorScheme.primary : Colors.grey,
                    ),
                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected ? theme.colorScheme.primary : null)),
                    subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => MusicPlayerService().playQueue(st.queue, startIndex: i),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}
