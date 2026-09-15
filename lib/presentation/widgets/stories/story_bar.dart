import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/story_model.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../screens/stories/story_viewer_screen.dart';
import '../../screens/stories/story_create_screen.dart';

final storyFeedProvider =
    StateNotifierProvider.autoDispose<StoryFeedNotifier, AsyncValue<List<StoryGroup>>>((ref) {
  final session = ref.watch(authenticatedSessionProvider);
  return StoryFeedNotifier(api: session.api, enabled: session.userId != null);
});

class StoryFeedNotifier extends StateNotifier<AsyncValue<List<StoryGroup>>> {
  StoryFeedNotifier({required this.api, required bool enabled})
      : _enabled = enabled,
        super(const AsyncValue.loading()) {
    if (enabled) {
      refresh();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh(silent: true));
    } else {
      state = const AsyncValue.data([]);
    }
  }

  final ApiService api;
  final bool _enabled;
  Timer? _timer;

  Future<void> refresh({bool silent = false}) async {
    if (!_enabled) return;
    if (!silent) state = const AsyncValue.loading();
    try {
      final res = await api.get('/stories/');
      final groups = (res['groups'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(StoryGroup.fromJson)
          .toList();
      if (mounted) state = AsyncValue.data(groups);
    } catch (e, st) {
      if (mounted && !silent) state = AsyncValue.error(e, st);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Telegram-like story tray shown on top of the chat list.
///
/// Every state (loading / empty / data / error) renders at exactly
/// [_trayHeight] so the chat list never jumps, and the avatar column is
/// height-bounded so a large system font cannot overflow the row.
class StoryBar extends ConsumerWidget {
  const StoryBar({super.key});

  static const double _trayHeight = 104;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(storyFeedProvider);
    final myId = ref.watch(authNotifierProvider).valueOrNull?.id;
    final theme = Theme.of(context);

    Widget shell(Widget child) => Container(
          height: _trayHeight,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
          ),
          child: child,
        );

    return feed.when(
      loading: () => shell(
        const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      // An error must not remove the tray: the user still needs "add story".
      error: (_, __) => shell(
        _StoryStrip(
          entries: [
            _StoryEntry.mine(onTap: () => _openCreate(context, ref)),
          ],
        ),
      ),
      data: (groups) {
        final mine = groups.where((g) => g.user.id == myId && g.stories.isNotEmpty).toList();
        final others = groups.where((g) => g.user.id != myId && g.stories.isNotEmpty).toList();
        final ordered = [...mine, ...others];

        final entries = <_StoryEntry>[
          _StoryEntry.mine(
            avatarUrl: mine.isNotEmpty ? mine.first.user.avatarUrl : null,
            displayName: mine.isNotEmpty ? mine.first.user.displayName : '',
            hasStory: mine.isNotEmpty,
            onTap: () => _openCreate(context, ref),
            onView: mine.isNotEmpty
                ? () => _openViewer(context, ref, ordered, 0)
                : null,
          ),
          for (var i = 0; i < others.length; i++)
            _StoryEntry(
              label: others[i].user.displayName,
              avatarUrl: others[i].user.avatarUrl,
              displayName: others[i].user.displayName,
              hasUnseen: others[i].hasUnseen,
              onTap: () => _openViewer(
                context,
                ref,
                ordered,
                mine.isNotEmpty ? i + 1 : i,
              ),
            ),
        ];

        return shell(_StoryStrip(entries: entries));
      },
    );
  }

  Future<void> _openCreate(BuildContext context, WidgetRef ref) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const StoryCreateScreen()),
    );
    if (created == true) ref.read(storyFeedProvider.notifier).refresh();
  }

  Future<void> _openViewer(
    BuildContext context,
    WidgetRef ref,
    List<StoryGroup> groups,
    int index,
  ) async {
    final visible = groups.where((g) => g.stories.isNotEmpty).toList();
    if (visible.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(
          groups: visible,
          initialGroupIndex: index.clamp(0, visible.length - 1),
        ),
      ),
    );
    ref.read(storyFeedProvider.notifier).refresh(silent: true);
  }
}

class _StoryEntry {
  final String label;
  final String? avatarUrl;
  final String displayName;
  final bool hasUnseen;
  final bool isMine;
  final bool hasStory;
  final VoidCallback onTap;
  final VoidCallback? onView;

  const _StoryEntry({
    required this.label,
    this.avatarUrl,
    required this.displayName,
    this.hasUnseen = false,
    this.isMine = false,
    this.hasStory = false,
    required this.onTap,
    this.onView,
  });

  factory _StoryEntry.mine({
    String? avatarUrl,
    String displayName = '',
    bool hasStory = false,
    required VoidCallback onTap,
    VoidCallback? onView,
  }) =>
      _StoryEntry(
        label: 'استوری من',
        avatarUrl: avatarUrl,
        displayName: displayName,
        isMine: true,
        hasStory: hasStory,
        onTap: onTap,
        onView: onView,
      );
}

class _StoryStrip extends StatelessWidget {
  final List<_StoryEntry> entries;
  const _StoryStrip({required this.entries});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, i) => _StoryAvatar(entry: entries[i]),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  final _StoryEntry entry;
  const _StoryAvatar({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showRing = entry.hasUnseen || (entry.isMine && entry.hasStory);
    final ringColor = entry.hasUnseen
        ? theme.colorScheme.primary
        : theme.dividerColor.withValues(alpha: 0.5);

    return GestureDetector(
      onTap: entry.isMine && entry.onView != null ? entry.onView : entry.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 66,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: showRing ? ringColor : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.15),
                    backgroundImage: entry.avatarUrl != null
                        ? NetworkImage(entry.avatarUrl!, headers: {
                            'Authorization':
                                'Bearer ${StorageService.getToken() ?? ""}',
                          })
                        : null,
                    child: entry.avatarUrl == null
                        ? Text(
                            entry.displayName.isNotEmpty
                                ? entry.displayName.characters.first
                                : '+',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                ),
                if (entry.isMine)
                  Positioned(
                    bottom: -1,
                    right: -1,
                    child: GestureDetector(
                      onTap: entry.onTap,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                        child: const Icon(Icons.add,
                            size: 11, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // Fixed slot for the caption: text can never push the column past
            // the tray height, whatever the system font scale is.
            SizedBox(
              height: 14,
              width: 66,
              child: Text(
                entry.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, height: 1.2),
                textScaler: TextScaler.noScaling,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
