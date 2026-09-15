import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chat/create_channel_screen.dart';

import 'main_shell.dart';
import 'archived_chats_screen.dart';
import 'folder_editor_screen.dart';

import '../../providers/chat_list_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../../data/models/chat_folder_model.dart';
import '../../../data/models/chat_model.dart';
import '../../../data/services/api_service.dart';
import '../chat/chat_screen.dart';
import '../../widgets/chat/chat_labels.dart';
import '../../widgets/chat/chat_list_actions.dart';
import '../../widgets/chat/chat_list_tile.dart';
import '../../widgets/chat/sponsored_banner.dart';
import '../../widgets/stories/story_bar.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  /// null = the "All" folder, [_personalFolderId] = the built in personal
  /// folder, anything else is a custom folder id.
  String? _selectedFolderId;

  static const String _personalFolderId = '__personal__';

  ChatFolderModel? _selectedFolder(List<ChatFolderModel> folders) {
    final id = _selectedFolderId;
    if (id == null || id == _personalFolderId) return null;
    for (final folder in folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  List<ChatModel> _visibleChats(
    List<ChatModel> chats,
    List<ChatFolderModel> folders, {
    List<ChatModel> archived = const [],
  }) {
    final id = _selectedFolderId;
    if (id == null) return chats;
    if (id == _personalFolderId) {
      return chats.where((c) => c.isPersonal).toList();
    }
    final folder = _selectedFolder(folders);
    if (folder == null) return chats;
    // A folder that includes the archive shows those chats inline, so the
    // archive row is not needed while such a folder is selected.
    final pool = folder.includeArchived ? [...chats, ...archived] : chats;
    return pool.where(folder.contains).toList();
  }

  @override
  Widget build(BuildContext context) {
    final chatsAsync = ref.watch(chatListProvider);
    final foldersAsync = ref.watch(chatFoldersProvider);
    final folders = foldersAsync.valueOrNull ?? const <ChatFolderModel>[];
    final locale = ref.watch(localeProvider);
    final isFa = locale.languageCode == 'fa';
    final labels = ChatLabels.of(context);
    final theme = Theme.of(context);

    // A folder that was deleted elsewhere must not keep the list empty.
    if (_selectedFolderId != null &&
        _selectedFolderId != _personalFolderId &&
        foldersAsync.hasValue &&
        !folders.any((f) => f.id == _selectedFolderId)) {
      _selectedFolderId = null;
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          isFa ? 'پیام‌رسان' : 'Messenger',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {
              ref.read(shellIndexProvider.notifier).state = 1;
            },
            tooltip: isFa ? 'جستجو' : 'Search',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => _onMenu(v, isFa),
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'saved',
                child: Text(isFa ? 'پیام‌های ذخیره‌شده' : 'Saved Messages'),
              ),
              PopupMenuItem(
                value: 'group',
                child: Text(isFa ? 'گروه جدید' : 'New Group'),
              ),
              PopupMenuItem(
                value: 'channel',
                child: Text(isFa ? 'کانال جدید' : 'New Channel'),
              ),
              PopupMenuItem(value: 'folder', child: Text(labels.newFolder)),
              PopupMenuItem(
                value: 'archive',
                child: Text(labels.archivedChats),
              ),
              PopupMenuItem(
                value: 'support',
                child: Text(isFa ? 'پشتیبانی' : 'Support'),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: _FolderBar(
            folders: folders,
            selectedId: _selectedFolderId,
            personalId: _personalFolderId,
            onSelected: (id) => setState(() => _selectedFolderId = id),
            onEdit: _openFolderEditor,
            onCreate: () => _openFolderEditor(null),
          ),
        ),
      ),
      body: SafeArea(
        child: chatsAsync.when(
          data: (data) {
            final folder = _selectedFolder(folders);
            final archived = folder?.includeArchived == true
                ? (ref.watch(archivedChatListProvider).valueOrNull?.chats ??
                      const <ChatModel>[])
                : const <ChatModel>[];
            final chats = _visibleChats(
              data.chats,
              folders,
              archived: archived,
            );
            // The archive row lives on top of the "All" folder, like Telegram.
            final showArchiveRow =
                _selectedFolderId == null && data.hasArchive;
            if (chats.isEmpty && !showArchiveRow) {
              return _EmptyState(
                isFa: isFa,
                inFolder: _selectedFolderId != null,
              );
            }
            final itemCount = chats.length + (showArchiveRow ? 1 : 0);
            return Column(
              children: [
                const _DeviceLoginBanner(),
                const StoryBar(),
                if (_selectedFolderId == null) const _SponsoredStrip(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => ref.read(chatListProvider.notifier).refresh(),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: itemCount,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 76,
                        color: Colors.grey.withValues(alpha: 0.15),
                      ),
                      itemBuilder: (context, index) {
                        if (showArchiveRow && index == 0) {
                          return _ArchiveRow(
                            state: data,
                            labels: labels,
                            onTap: _openArchive,
                          );
                        }
                        final chat = chats[index - (showArchiveRow ? 1 : 0)];
                        return ChatListTile(
                              key: ValueKey(chat.id),
                              chat: chat,
                              isFa: isFa,
                              onTap: () => _openChat(chat),
                              onLongPress: () =>
                                  showChatContextMenu(context, ref, chat),
                            )
                            .animate()
                            .fadeIn(duration: 280.ms, delay: (20 * (index % 12)).ms)
                            .slideX(begin: 0.05, curve: Curves.easeOut);
                      },
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isFa ? 'خطا در بارگذاری' : 'Failed to load',
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () =>
                      ref.read(chatListProvider.notifier).refresh(),
                  child: Text(isFa ? 'تلاش مجدد' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      // بدون FloatingActionButton مداد
    );
  }

  void _openChat(ChatModel chat) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chat.id,
          title: chat.displayTitle,
          chatType: chat.chatType,
          otherUser: chat.otherUser,
          avatarUrl: chat.avatarUrl,
        ),
      ),
    );
  }

  Future<void> _openArchive() async {
    await openArchivedChats(context, ref);
    if (!mounted) return;
    ref.read(chatListProvider.notifier).refresh();
  }

  Future<void> _openFolderEditor(ChatFolderModel? folder) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FolderEditorScreen(folder: folder)),
    );
    if (!mounted) return;
    if (saved == true) {
      await ref.read(chatFoldersProvider.notifier).load();
    }
  }

  Future<void> _onMenu(String value, bool isFa) async {
    try {
      if (value == 'saved') {
        final res = await ApiService().post('/chats/saved', {});
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId: res['chat_id'] as String,
              title: isFa ? 'پیام‌های ذخیره‌شده' : 'Saved Messages',
              chatType: 'saved',
            ),
          ),
        );
      } else if (value == 'support') {
        final res = await ApiService().post('/chats/support', {});
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId: res['chat_id'] as String,
              title: isFa ? 'پشتیبانی' : 'Support',
              chatType: 'support',
            ),
          ),
        );
      } else if (value == 'group') {
        await _createGroupDialog(isFa);
      } else if (value == 'channel') {
        await _createChannelDialog(isFa);
      } else if (value == 'folder') {
        await _openFolderEditor(null);
        return;
      } else if (value == 'archive') {
        await _openArchive();
        return;
      }
      ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _createGroupDialog(bool isFa) async {
    final titleCtrl = TextEditingController();
    final List<String> selectedIds = [];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFa ? 'گروه جدید' : 'New Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: isFa ? 'نام گروه' : 'Group name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isFa ? 'لغو' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isFa ? 'ایجاد' : 'Create'),
          ),
        ],
      ),
    );
    if (ok == true && titleCtrl.text.trim().isNotEmpty) {
      final res = await ApiService().post('/chats/group', {
        'title': titleCtrl.text.trim(),
        'member_ids': selectedIds,
      });
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: res['chat_id'] as String,
            title: titleCtrl.text.trim(),
            chatType: 'group',
          ),
        ),
      );
    }
  }

  Future<void> _createChannelDialog(bool isFa) async {
    final session = ref.read(authenticatedSessionProvider);
    final created = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => CreateChannelScreen(api: session.api)),
    );
    if (!mounted || created == null) return;
    ref.read(chatListProvider.notifier).refresh();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: created['chat_id'] as String,
          title: created['title'] as String,
          chatType: 'channel',
        ),
      ),
    );
  }
}

/// Horizontal folder strip: All | Personal | custom folders | +
class _FolderBar extends StatelessWidget {
  const _FolderBar({
    required this.folders,
    required this.selectedId,
    required this.personalId,
    required this.onSelected,
    required this.onEdit,
    required this.onCreate,
  });

  final List<ChatFolderModel> folders;
  final String? selectedId;
  final String personalId;
  final ValueChanged<String?> onSelected;
  final ValueChanged<ChatFolderModel> onEdit;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final labels = ChatLabels.of(context);
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _chip(context, labels.folderAll, null),
          _chip(context, labels.folderPersonal, personalId),
          for (final folder in folders)
            _chip(context, folder.name, folder.id, folder: folder),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: IconButton(
              key: const ValueKey('folder-add'),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              tooltip: labels.newFolder,
              icon: const Icon(Icons.add_rounded),
              onPressed: onCreate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    String? id, {
    ChatFolderModel? folder,
  }) {
    final selected = selectedId == id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: GestureDetector(
        onLongPress: folder == null ? null : () => onEdit(folder),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onSelected(id),
        ),
      ),
    );
  }
}

class _ArchiveRow extends StatelessWidget {
  const _ArchiveRow({
    required this.state,
    required this.labels,
    required this.onTap,
  });

  final ChatListState state;
  final ChatLabels labels;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: const ValueKey('archive-row'),
      onTap: onTap,
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.blueGrey.withValues(alpha: 0.2),
        child: Icon(
          state.hasArchivePin ? Icons.lock_outline : Icons.archive_outlined,
          color: Colors.blueGrey,
        ),
      ),
      title: Text(
        labels.archivedChats,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text('${state.archivedTotal}'),
      trailing: state.archivedUnread > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                state.archivedUnread > 99 ? '99+' : '${state.archivedUnread}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : const Icon(Icons.chevron_right_rounded),
    );
  }
}


class _DeviceLoginBanner extends StatefulWidget {
  const _DeviceLoginBanner();
  @override
  State<_DeviceLoginBanner> createState() => _DeviceLoginBannerState();
}
class _DeviceLoginBannerState extends State<_DeviceLoginBanner> {
  List<dynamic> _notifs = [];
  bool _dismissed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }
  Future<void> _load() async {
    try {
      final res = await ApiService().get('/devices/notifications');
      final list = res['messages'] as List? ?? res['notifications'] as List? ?? [];
      if (mounted && list.isNotEmpty) setState(()=> _notifs = list.take(1).toList());
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    if (_dismissed || _notifs.isEmpty) return const SizedBox.shrink();
    final msg = _notifs.first as Map<String,dynamic>;
    final content = (msg['content'] as String? ?? 'ورود جدید به حساب شما').split('\n').first;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
      child: Row(children: [
        const Icon(Icons.security, color: Colors.orange, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(content, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87), maxLines: 2, overflow: TextOverflow.ellipsis),
          const Text('این هشدار مانند تلگرام در «پیام‌های ذخیره‌شده» هم ذخیره شده است. اگر شما نبودید، فوراً رمز را تغییر دهید و نشست را ببندید.', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ])),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: ()=> setState(()=> _dismissed=true)),
      ]),
    );
  }
}

/// Sponsored channels strip (visible to everyone, set by the general admin).
class _SponsoredStrip extends StatefulWidget {
  const _SponsoredStrip();
  @override
  State<_SponsoredStrip> createState() => _SponsoredStripState();
}

class _SponsoredStripState extends State<_SponsoredStrip> {
  List<ChatModel> _channels = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().get('/chats/sponsored');
      if (!mounted) return;
      final list = (res['channels'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ChatModel.fromJson)
          .toList();
      setState(() => _channels = list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => SponsoredBanner(channels: _channels);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isFa, required this.inFolder});

  final bool isFa;
  final bool inFolder;

  @override
  Widget build(BuildContext context) {
    final labels = ChatLabels.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            inFolder
                ? Icons.folder_open_rounded
                : Icons.chat_bubble_outline_rounded,
            size: 72,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            inFolder
                ? labels.folderEmpty
                : (isFa ? 'هنوز گفتگویی ندارید' : 'No conversations yet'),
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            isFa
                ? 'از تب جستجو کاربر پیدا کنید'
                : 'Find users from the Search tab',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ],
      ),
    );
  }
}
