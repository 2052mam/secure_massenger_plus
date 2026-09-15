import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../data/models/chat_folder_model.dart';
import '../../data/models/chat_model.dart';
import '../../data/services/api_service.dart';
import '../../data/services/archive_lock_service.dart';
import 'auth_provider.dart';

/// The main (non archived) chat list plus the archive summary shown on top of
/// it, exactly like Telegram's collapsed "Archived chats" row.
class ChatListState {
  const ChatListState({
    this.chats = const [],
    this.archivedTotal = 0,
    this.archivedUnread = 0,
    this.archivedChatsWithUnread = 0,
    this.hasArchivePin = false,
    this.archiveLocked = false,
  });

  final List<ChatModel> chats;
  final int archivedTotal;
  final int archivedUnread;
  final int archivedChatsWithUnread;
  final bool hasArchivePin;
  final bool archiveLocked;

  bool get hasArchive => archivedTotal > 0;

  factory ChatListState.fromJson(Map<String, dynamic> json) {
    final archived = json['archived'] as Map<String, dynamic>? ?? const {};
    return ChatListState(
      chats: (json['chats'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ChatModel.fromJson)
          .toList(),
      archivedTotal: archived['total'] as int? ?? 0,
      archivedUnread: archived['unread'] as int? ?? 0,
      archivedChatsWithUnread: archived['chats_with_unread'] as int? ?? 0,
      hasArchivePin: json['has_archive_pin'] as bool? ?? false,
      archiveLocked: json['archive_locked'] as bool? ?? false,
    );
  }
}

final archiveLockProvider = Provider<ArchiveLockService>((ref) {
  final session = ref.watch(authenticatedSessionProvider);
  return ArchiveLockService(session.api, userId: session.userId);
});

final chatListProvider =
    StateNotifierProvider.autoDispose<ChatListNotifier, AsyncValue<ChatListState>>(
      (ref) {
        final session = ref.watch(authenticatedSessionProvider);
        return ChatListNotifier(
          api: session.api,
          enabled: session.userId != null,
        );
      },
    );

/// Archived chats are fetched on demand, only while the archive is unlocked.
final archivedChatListProvider =
    StateNotifierProvider.autoDispose<ChatListNotifier, AsyncValue<ChatListState>>(
      (ref) {
        final session = ref.watch(authenticatedSessionProvider);
        final lock = ref.watch(archiveLockProvider);
        return ChatListNotifier(
          api: session.api,
          enabled: session.userId != null,
          archived: true,
          lock: lock,
        );
      },
    );

final chatFoldersProvider =
    StateNotifierProvider.autoDispose<ChatFoldersNotifier, AsyncValue<List<ChatFolderModel>>>(
      (ref) {
        final session = ref.watch(authenticatedSessionProvider);
        return ChatFoldersNotifier(
          api: session.api,
          enabled: session.userId != null,
        );
      },
    );

class ChatListNotifier extends StateNotifier<AsyncValue<ChatListState>> {
  ChatListNotifier({
    ApiService? api,
    bool enabled = true,
    bool archived = false,
    ArchiveLockService? lock,
  }) : _api = api ?? ApiService(),
       _enabled = enabled,
       _archived = archived,
       _lock = lock,
       super(
         enabled
             ? const AsyncValue.loading()
             : const AsyncValue.data(ChatListState()),
       ) {
    if (enabled) {
      unawaited(loadChats());
      _pollTimer = Timer.periodic(
        const Duration(seconds: ApiConstants.pollingIntervalSeconds),
        (_) => loadChats(),
      );
    }
  }

  final ApiService _api;
  final bool _enabled;
  final bool _archived;
  final ArchiveLockService? _lock;
  Timer? _pollTimer;
  Future<void>? _loading;

  Future<void> loadChats() {
    if (!mounted || !_enabled) return Future<void>.value();
    // Polling and a read/send/delete refresh can happen together. Share the
    // request rather than allowing an older response to replace newer state.
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      final res = await _api.get(
        '/chats/',
        query: _archived ? const {'archived': '1'} : null,
        headers: _archived ? _lock?.headers : null,
      );
      if (!mounted) return;
      state = AsyncValue.data(ChatListState.fromJson(res));
    } catch (error, stack) {
      if (!mounted) return;
      // A locked archive is a real error for the archive screen, but the main
      // list must not flash an error/loading screen on each background poll.
      if (!state.hasValue) state = AsyncValue.error(error, stack);
    }
  }

  Future<void> refresh() => loadChats();

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

class ChatFoldersNotifier
    extends StateNotifier<AsyncValue<List<ChatFolderModel>>> {
  ChatFoldersNotifier({ApiService? api, bool enabled = true})
    : _api = api ?? ApiService(),
      _enabled = enabled,
      super(
        enabled
            ? const AsyncValue.loading()
            : const AsyncValue.data(<ChatFolderModel>[]),
      ) {
    if (enabled) unawaited(load());
  }

  final ApiService _api;
  final bool _enabled;

  Future<void> load() async {
    if (!mounted || !_enabled) return;
    try {
      final res = await _api.get('/chats/folders');
      if (!mounted) return;
      final folders =
          (res['folders'] as List? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(ChatFolderModel.fromJson)
              .toList()
            ..sort((a, b) => a.position.compareTo(b.position));
      state = AsyncValue.data(folders);
    } catch (error, stack) {
      if (!mounted) return;
      if (!state.hasValue) state = AsyncValue.error(error, stack);
    }
  }

  Future<void> save(ChatFolderModel folder, {String? id}) async {
    await _api.post(
      id == null ? '/chats/folders' : '/chats/folders/$id',
      folder.toRequestBody(),
    );
    await load();
  }

  Future<void> remove(String id) async {
    await _api.post('/chats/folders/$id/delete', {});
    await load();
  }
}
