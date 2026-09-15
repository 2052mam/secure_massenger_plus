import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/search_history_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/storage_service.dart';
import '../../widgets/chat/chat_avatar.dart';
import '../../widgets/chat/chat_labels.dart';
import '../../providers/locale_provider.dart';
import '../chat/chat_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  List<UserModel> _users = [];
  List<Map<String, dynamic>> _channels = [];
  List<SearchHistoryItem> _history = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  bool get _hasQuery => _ctrl.text.trim().length >= 2;

  /// Recent searches survive deleting a chat, so a person found once can
  /// always be reached again — the way Telegram's search tab behaves.
  Future<void> _loadHistory() async {
    try {
      final res = await ApiService().get('/users/search-history');
      if (!mounted) return;
      setState(() => _history = SearchHistoryItem.listFrom(res));
    } catch (_) {
      // History is a convenience; searching still works without it.
    }
  }

  Future<void> _remember({
    String? query,
    String? userId,
    String? chatId,
  }) async {
    try {
      await ApiService().post('/users/search-history', {
        if (query != null && query.isNotEmpty) 'query': query,
        if (userId != null) 'user_id': userId,
        if (chatId != null) 'chat_id': chatId,
      });
      await _loadHistory();
    } catch (_) {}
  }

  Future<void> _removeHistory(SearchHistoryItem item) async {
    setState(() => _history = [..._history]..remove(item));
    try {
      await ApiService().post('/users/search-history/${item.id}/delete', {});
    } catch (_) {}
    await _loadHistory();
  }

  Future<void> _clearHistory() async {
    setState(() => _history = []);
    try {
      await ApiService().post('/users/search-history/clear', {});
    } catch (_) {}
    await _loadHistory();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() {
        _users = [];
        _channels = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService().get(
        '/users/search',
        query: {'q': q.trim()},
      );
      final list = (res['users'] as List? ?? [])
          .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final chans = (res['chats'] as List? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      if (!mounted) return;
      setState(() {
        _users = list;
        _channels = chans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _startChat(UserModel user, {bool remember = true}) async {
    try {
      final res = await ApiService().post('/chats/private', {
        'user_id': user.id,
      });
      if (remember) {
        unawaited(_remember(query: _ctrl.text.trim(), userId: user.id));
      }
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: res['chat_id'] as String,
            title: user.displayName,
            chatType: 'private',
            otherUser: user,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _joinChannel(Map<String, dynamic> ch) async {
    try {
      final chatId = ch['id'] as String;
      final title = ch['title'] as String? ?? '';
      // Only open after the server confirms membership; an access error is
      // not evidence that we were already a member.
      await ApiService().post('/chats/$chatId/add-member', {
        'user_id': (await ApiService().get('/users/me'))['id'],
      });
      await _remember(query: _ctrl.text.trim(), chatId: chatId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(chatId: chatId, title: title, chatType: 'channel'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _openHistoryItem(SearchHistoryItem item) async {
    final user = item.user;
    if (user != null) {
      await _startChat(user, remember: false);
      unawaited(_remember(query: item.query, userId: user.id));
      return;
    }
    final chat = item.chat;
    if (chat != null) {
      await _joinChannel({
        'id': chat.id,
        'title': chat.title,
        'username': chat.username,
      });
      return;
    }
    final query = item.query;
    if (query != null && query.isNotEmpty) {
      _ctrl.text = query;
      _ctrl.selection = TextSelection.collapsed(offset: query.length);
      await _search(query);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';
    final labels = ChatLabels.of(context);
    final showHistory = !_hasQuery && _history.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(isFa ? 'جستجو' : 'Search')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _ctrl,
                onChanged: (q) {
                  setState(() {});
                  _search(q);
                },
                onSubmitted: (q) {
                  if (q.trim().length >= 2) _remember(query: q.trim());
                },
                decoration: InputDecoration(
                  hintText: isFa
                      ? 'جستجو کاربر یا کانال...'
                      : 'Search user or channel...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _ctrl.clear();
                            _search('');
                            setState(() {});
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Expanded(
              child: ListView(
                children: [
                  if (showHistory) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 8,
                        top: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              labels.recentSearches,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            key: const ValueKey('clear-search-history'),
                            onPressed: _clearHistory,
                            child: Text(labels.clearAll),
                          ),
                        ],
                      ),
                    ),
                    ..._history.map(
                      (item) => ListTile(
                        key: ValueKey('history-${item.id}'),
                        leading: item.user != null
                            ? ChatAvatar(
                                title: item.user!.displayName,
                                url: item.user!.showProfilePhoto
                                    ? item.user!.avatarUrl
                                    : null,
                                token: StorageService.getToken(),
                              )
                            : CircleAvatar(
                                child: Icon(
                                  item.chat != null
                                      ? Icons.campaign
                                      : Icons.history,
                                ),
                              ),
                        title: Text(item.title),
                        subtitle: item.subtitle == null
                            ? null
                            : Text(item.subtitle!),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _removeHistory(item),
                        ),
                        onTap: () => _openHistoryItem(item),
                      ),
                    ),
                    const Divider(),
                  ],
                  if (_users.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        isFa ? 'کاربران' : 'Users',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ..._users.map(
                      (u) => ListTile(
                        leading: ChatAvatar(
                          title: u.displayName,
                          url: u.avatarUrl,
                          token: StorageService.getToken(),
                        ),
                        title: Text(u.displayName),
                        subtitle: Text(u.handle),
                        trailing: const Icon(Icons.chat_bubble_outline),
                        onTap: () => _startChat(u),
                      ),
                    ),
                  ],
                  if (_channels.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        isFa ? 'کانال‌ها' : 'Channels',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ..._channels.map(
                      (ch) => ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.campaign),
                        ),
                        title: Text(ch['title'] ?? ''),
                        subtitle: ch['username'] != null
                            ? Text('@${ch['username']}')
                            : null,
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _joinChannel(ch),
                      ),
                    ),
                  ],
                  if (_users.isEmpty &&
                      _channels.isEmpty &&
                      !_loading &&
                      !showHistory)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          isFa
                              ? 'حداقل ۲ کاراکتر وارد کنید'
                              : 'Enter at least 2 characters',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
