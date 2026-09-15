import 'package:file_picker/file_picker.dart';
import '../../widgets/chat/scheduled_messages_sheet.dart';
import '../../../core/utils/api_datetime.dart';
import 'chat_management_screen.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';

import '../../../data/models/message_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/chat_invite_model.dart';
import '../../../data/services/message_reconciler.dart';
import '../../../core/utils/chat_invite_link.dart';
import '../../../data/models/reply_preview_model.dart';
import '../../../data/services/media_playback_coordinator.dart';
import '../../../core/utils/media_utils.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/voice_service.dart';
import '../../../data/services/location_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_list_provider.dart';
import '../profile/user_profile_screen.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/chat_header.dart';
import '../../widgets/chat/chat_labels.dart';
import '../../widgets/chat/chat_invite_dialog.dart';
import '../../widgets/chat/message_actions_sheet.dart';
import '../../widgets/chat/pinned_messages_bar.dart';
import '../../widgets/chat/reaction_bar.dart';
import '../../widgets/chat/sticker_picker.dart';
import '../../widgets/chat/gif_picker.dart';
import '../../widgets/chat/report_dialog.dart';
import '../../widgets/chat/encrypted_bubble.dart';
import '../../../data/services/encryption_service.dart';
import '../../widgets/media/video_note_player.dart';
import '../../widgets/music/mini_music_player.dart';
import 'pinned_messages_screen.dart';
import 'location_picker_screen.dart';
import 'secure_chat_screen.dart';
import 'photo_editor_screen.dart';
import 'video_editor_screen.dart';
import '../../widgets/chat/reply_preview.dart';
import '../../widgets/media/media_labels.dart';
import '../media/photo_viewer_screen.dart';
import '../media/view_once_photo_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String title;
  final String chatType;
  final UserModel? otherUser;
  final String? avatarUrl;
  const ChatScreen({
    super.key,
    required this.chatId,
    required this.title,
    this.chatType = 'private',
    this.otherUser,
    this.avatarUrl,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  late ApiService _api;
  late String? _authToken;
  late final String? _sessionUserId;
  final _reconciler = MessageReconciler();
  UserModel? _otherUser;
  String? _loadedChatType;
  String? _chatTitle;
  String? _chatAvatarUrl;
  bool _hasChatInfo = false;
  bool _refreshingChatInfo = false;
  bool _chatUnavailable = false;
  bool _allowForwarding = true;
  bool _openingInvite = false;
  Route<void>? _photoRoute;
  String? _photoMessageId;
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  final List<MessageModel> _messages = [];
  final VoiceService _voice = VoiceService();
  final _playback = MediaPlaybackCoordinator();
  final Map<String, GlobalKey> _messageKeys = {};
  Timer? _highlightTimer;
  String? _highlightedMessageId;
  bool _openingMedia = false;
  bool _jumpingToReply = false;
  bool _historyMode = false;
  bool _hasEarlier = false;
  bool _loadingEarlier = false;
  bool _polling = false;
  bool _refreshingStatuses = false;
  int _loadGeneration = 0;
  bool _loading = true;
  bool _sending = false;
  bool _searchMode = false;
  String? _error;
  Timer? _pollTimer;
  String? _lastMessageId;
  String? _currentUserId;
  MessageModel? _replyTo;
  Color? _bgColor;
  String? _bgImageUrl;
  bool _isRecording = false;
  String? _myRole;
  Map<String, dynamic> _capabilities = {};
  bool _isMuted = false;
  bool _muting = false;
  final List<MessageModel> _pinned = [];
  int _pinnedIndex = 0;
  bool _canPinMessages = false;
  bool _loadingPinned = false;
  bool _isSpoiler = false;
  int _slowModeDelay = 0;
  int _slowModeRemaining = 0;
  Timer? _slowModeTimer;
  // True while this chat has an ongoing (non-erased) secure conversation.
  bool _hasSecureSession = false;
  // Live location: id of the message currently being broadcast + its ticker.
  String? _liveLocationMessageId;
  DateTime? _liveLocationUntil;
  Timer? _liveLocationTimer;

  bool _can(String right) {
    if (_chatUnavailable) return false;
    if (_chatType != 'group' && _chatType != 'channel') return true;
    return _capabilities[right] == true;
  }

  bool _canDelete(MessageModel msg) {
    if (_chatType == 'private' || _chatType == 'saved') return true;
    if (_chatType == 'support')
      return msg.senderId == _currentUserId ||
          _myRole == 'owner' ||
          _myRole == 'admin';
    if (_chatType == 'channel') return _can('delete_messages');
    return _can('delete_messages') ||
        (msg.senderId == _currentUserId && _can('delete_own_messages'));
  }

  int _membersCount = 0;
  int _onlineCount = 0;
  bool _hideMembers = false;
  bool _isSuspended = false;
  String? _suspensionReason;
  bool _isClosed = false;
  String? _closedReason;

  String get _chatType => _loadedChatType ?? widget.chatType;
  String get _displayTitle =>
      _otherUser?.displayName ?? _chatTitle ?? widget.title;
  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  String _mediaFullUrl(String? mediaId, {String? existingUrl}) =>
      resolveMediaUrl(mediaId, existingUrl: existingUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final session = ref.read(authenticatedSessionProvider);
    _sessionUserId = session.userId;
    _authToken = session.token;
    _api = session.api;
    _otherUser = widget.otherUser;
    _chatAvatarUrl = widget.avatarUrl;
    _currentUserId =
        ref.read(authNotifierProvider).valueOrNull?.id ??
        StorageService.getUserId();
    _loadMessages();
    _startPolling();
    _loadBackground();
    _loadChatInfo();
    _loadPinned();
    _checkSecureSession();
  }

  Future<void> _loadBackground() async {
    try {
      final res = await _api.get('/chats/${widget.chatId}/background');
      final bg = res['background'] as Map<String, dynamic>?;
      if (bg == null) return;
      final type = bg['type'] as String?;
      final value = bg['value'] as String?;
      if (value == null || value.isEmpty) return;
      if (type == 'image') {
        if (mounted) setState(() => _bgImageUrl = value);
      } else if (type == 'color') {
        final hex = value.replaceFirst('#', '');
        final colorValue = int.tryParse(hex, radix: 16);
        if (colorValue != null && mounted) {
          setState(() => _bgColor = Color(colorValue | 0xFF000000));
        }
      }
    } catch (_) {}
  }

  Future<void> _loadChatInfo() async {
    if (!mounted || _refreshingChatInfo || _chatUnavailable) return;
    _refreshingChatInfo = true;
    try {
      final res = await _api.get('/chats/${widget.chatId}/info');
      if (!mounted) return;
      if (res['my_role'] == null &&
          ['group', 'channel'].contains(res['chat_type'])) {
        _showChatUnavailable();
        return;
      }
      setState(() {
        _myRole = res['my_role'] as String?;
        _capabilities = Map<String, dynamic>.from(
          res['capabilities'] as Map? ?? {},
        );
        _isMuted = res['is_muted'] as bool? ?? false;
        _slowModeDelay = res['slow_mode_delay'] as int? ?? 0;
        _membersCount = res['members_count'] as int? ?? 0;
        _onlineCount = res['online_count'] as int? ?? 0;
        _hideMembers = res['hide_members'] as bool? ?? false;
        _isSuspended = res['is_suspended'] as bool? ?? false;
        _suspensionReason = res['suspension_reason'] as String?;
        _isClosed = res['is_closed'] as bool? ?? false;
        _closedReason = res['closed_reason'] as String?;
        _loadedChatType = res['chat_type'] as String?;
        _allowForwarding = res['allow_forwarding'] as bool? ?? true;
        _chatTitle = res['title'] as String?;
        _chatAvatarUrl = res['avatar_url'] as String?;
        _otherUser = res['other_user'] is Map<String, dynamic>
            ? UserModel.fromJson(res['other_user'] as Map<String, dynamic>)
            : null;
        _hasChatInfo = true;
        if (!_can('send_messages')) _replyTo = null;
      });
      if (_isRecording && !_can('send_voice')) {
        setState(() => _isRecording = false);
        await _voice.cancelRecording();
      }
    } on ApiException catch (error) {
      if ([403, 404].contains(error.statusCode)) _showChatUnavailable();
    } catch (_) {
      // Keep the last known profile during a temporary network failure.
    } finally {
      _refreshingChatInfo = false;
    }
  }

  void _showChatUnavailable() {
    if (!mounted || _chatUnavailable) return;
    _pollTimer?.cancel();
    unawaited(_playback.pause());
    final route = _photoRoute;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
    setState(() {
      ++_loadGeneration;
      _chatUnavailable = true;
      _loading = false;
      _error = ChatLabels.of(context).chatUnavailable;
      _messages.clear();
      _messageKeys.clear();
      _replyTo = null;
    });
  }

  @override
  void dispose() {
    ++_loadGeneration;
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _highlightTimer?.cancel();
    _slowModeTimer?.cancel();
    _liveLocationTimer?.cancel();
    unawaited(_playback.pause());
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_playback.pause());
    } else {
      _pollNow();
    }
  }

  Future<void> _markChatRead() async {
    if (!mounted ||
        !_foreground ||
        _chatUnavailable ||
        ModalRoute.of(context)?.isCurrent == false)
      return;
    try {
      await _api.post('/messages/chat/${widget.chatId}/read', {});
      if (!mounted) return;
      ref.read(chatListProvider.notifier).refresh();
    } catch (_) {}
  }

  Future<void> _loadMessages({String? query}) async {
    if (!mounted || _chatUnavailable) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> res;
      if (query != null && query.length >= 2) {
        res = await _api.get(
          '/messages/search/${widget.chatId}',
          query: {'q': query},
        );
      } else {
        res = await _api.get('/messages/${widget.chatId}');
      }
      if (!mounted || generation != _loadGeneration) return;
      final rawMessages = (res['messages'] as List? ?? [])
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final list = _reconciler.reconcile(rawMessages);
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _messageKeys.removeWhere((id, _) => !list.any((m) => m.id == id));
        if (query == null) {
          _lastMessageId = rawMessages.isEmpty ? null : rawMessages.last.id;
        }
        _hasEarlier = query == null && res['has_more'] == true;
        _historyMode = false;
        _loading = false;
      });
      unawaited(_refreshMessageStatuses());
      if (query == null) {
        _scrollToBottom();
        _markChatRead();
      }
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      if (e is ApiException && [403, 404].contains(e.statusCode)) {
        _showChatUnavailable();
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _mergeMessages(Iterable<MessageModel> messages) {
    for (final message in _reconciler.reconcile(messages)) {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index == -1) {
        _messages.add(message);
      } else {
        final previous = _messages[index];
        _messages[index] = message.copyWith(
          status: MessageReconciler.newestStatus(
            previous.status,
            message.status,
          ),
          viewedAt: previous.viewedAt ?? message.viewedAt,
        );
      }
    }
    _messages.sort((a, b) {
      final order = a.createdAt.compareTo(b.createdAt);
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    // Only history/new-message polls advance the server cursor. A send or
    // an older page must not skip remote messages still waiting to be polled.
  }

  Future<void> _loadEarlier() async {
    if (_loadingEarlier || _messages.isEmpty || !_hasEarlier) return;
    final generation = _loadGeneration;
    setState(() => _loadingEarlier = true);
    final oldExtent = _scrollCtrl.hasClients
        ? _scrollCtrl.position.maxScrollExtent
        : 0.0;
    final oldOffset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    try {
      final res = await _api.get(
        '/messages/${widget.chatId}',
        query: {'before_id': _messages.first.id},
      );
      if (!mounted || generation != _loadGeneration) return;
      final list = (res['messages'] as List? ?? []).map(
        (e) => MessageModel.fromJson(e as Map<String, dynamic>),
      );
      setState(() {
        _mergeMessages(list);
        _hasEarlier = res['has_more'] == true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_scrollCtrl.hasClients ||
            generation != _loadGeneration)
          return;
        final offset =
            oldOffset + _scrollCtrl.position.maxScrollExtent - oldExtent;
        _scrollCtrl.jumpTo(
          offset.clamp(0.0, _scrollCtrl.position.maxScrollExtent).toDouble(),
        );
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  ReplyPreviewModel? _replyPreviewFor(MessageModel message) {
    if (message.replyTo != null) return message.replyTo;
    final id = message.replyToId;
    if (id == null) return null;
    return _messages.firstWhereOrNull((m) => m.id == id)?.asReplyPreview ??
        ReplyPreviewModel.unavailable(id);
  }

  Future<void> _jumpToReply(String id) async {
    if (_jumpingToReply || _reconciler.isUnavailable(id)) return;
    _jumpingToReply = true;
    try {
      var target = _messageKeys[id]?.currentContext;
      if (target == null) {
        final generation = ++_loadGeneration;
        // Start the history window at the original, so it can be reached even
        // outside the lazy list's built items without an estimated pixel jump.
        final res = await _api.get(
          '/messages/${widget.chatId}',
          query: {'from_id': id},
        );
        if (!mounted || generation != _loadGeneration) return;
        final list = (res['messages'] as List? ?? [])
            .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isEmpty || list.first.id != id)
          throw StateError('Message unavailable');
        await _playback.pause();
        if (!mounted) return;
        setState(() {
          _messages
            ..clear()
            ..addAll(_reconciler.reconcile(list));
          _historyMode = true;
          _searchMode = false;
          _hasEarlier = true;
          _loading = false;
          _error = null;
        });
        if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        target = _messageKeys[id]?.currentContext;
      }
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.25,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted) return;
      _highlightTimer?.cancel();
      setState(() => _highlightedMessageId = id);
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightedMessageId = null);
      });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(MediaLabels.of(context).unavailable)),
        );
    } finally {
      _jumpingToReply = false;
    }
  }

  /// The pinned bar is chat state, not message state: it must survive
  /// scrolling, search and history mode, so it is loaded separately.
  Future<void> _loadPinned() async {
    if (!mounted || _loadingPinned || _chatUnavailable) return;
    _loadingPinned = true;
    try {
      final res = await _api.get('/messages/chat/${widget.chatId}/pinned');
      if (!mounted) return;
      final list = (res['messages'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(MessageModel.fromJson)
          .where((m) => !_reconciler.isUnavailable(m.id))
          .toList();
      final canPin = res['can_pin'] == true;
      if (const ListEquality<MessageModel>().equals(_pinned, list) &&
          canPin == _canPinMessages) {
        return;
      }
      setState(() {
        _pinned
          ..clear()
          ..addAll(list);
        _canPinMessages = canPin;
        if (_pinnedIndex >= _pinned.length) _pinnedIndex = 0;
      });
    } catch (_) {
      // The bar simply stays as it is; the next poll retries.
    } finally {
      _loadingPinned = false;
    }
  }

  Future<void> _togglePin(MessageModel msg, bool pin) async {
    try {
      await _api.post('/messages/${msg.id}/${pin ? 'pin' : 'unpin'}', {});
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((m) => m.id == msg.id);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(isPinned: pin);
        }
        if (!pin) {
          _pinned.removeWhere((m) => m.id == msg.id);
          if (_pinnedIndex >= _pinned.length) _pinnedIndex = 0;
        }
      });
      await _loadPinned();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _unpinAll() async {
    try {
      await _api.post('/messages/chat/${widget.chatId}/unpin-all', {});
      if (!mounted) return;
      setState(() {
        _pinned.clear();
        _pinnedIndex = 0;
      });
      await _loadPinned();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _openPinnedMessages() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => PinnedMessagesScreen(
          pinned: List<MessageModel>.from(_pinned),
          canPin: _canPinMessages,
          onUnpin: (message) => unawaited(_togglePin(message, false)),
          onUnpinAll: _unpinAll,
        ),
      ),
    );
    if (!mounted || id == null) return;
    await _jumpToReply(id);
  }

  void _tapPinnedBar() {
    if (_pinned.isEmpty) return;
    final index = _pinnedIndex < _pinned.length ? _pinnedIndex : 0;
    final message = _pinned[index];
    setState(() => _pinnedIndex = (index + 1) % _pinned.length);
    unawaited(_jumpToReply(message.id));
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: ApiConstants.pollingIntervalSeconds),
      (_) => _pollNow(),
    );
  }

  void _pollNow() {
    if (!mounted || !_foreground || _chatUnavailable) return;
    unawaited(_loadChatInfo());
    if (_loading) return;
    if (!_searchMode && !_historyMode) unawaited(_pollNewMessages());
    unawaited(_loadPinned());
    // Reconcile all loaded pages, even in search/history and after read ticks.
    unawaited(_refreshMessageStatuses());
  }

  void _applyMessageUpdate(MessageSyncResult update) {
    if (!mounted) return;
    final updated = _reconciler.reconcile(_messages, update: update);
    final clearReply =
        _replyTo != null && _reconciler.isUnavailable(_replyTo!.id);
    if (const ListEquality<MessageModel>().equals(_messages, updated) &&
        !clearReply)
      return;
    final removedMedia = _messages.any(
      (m) => update.deletedIds.contains(m.id) && m.mediaId != null,
    );
    if (removedMedia) unawaited(_playback.pause());
    setState(() {
      _messages
        ..clear()
        ..addAll(updated);
      _messageKeys.removeWhere((id, _) => _reconciler.isUnavailable(id));
      if (clearReply) _replyTo = null;
      if (_highlightedMessageId != null &&
          _reconciler.isUnavailable(_highlightedMessageId!)) {
        _highlightedMessageId = null;
      }
    });
    // Close only the deleted photo's route, never an unrelated dialog/chat.
    final photoRoute = _photoRoute;
    if (photoRoute != null &&
        photoRoute.isActive &&
        _photoMessageId != null &&
        update.deletedIds.contains(_photoMessageId)) {
      photoRoute.navigator?.removeRoute(photoRoute);
    }
    if (update.deletedIds.isNotEmpty) {
      unawaited(ref.read(chatListProvider.notifier).refresh());
    }
    final pinnedIds = update.pinnedIds;
    if (pinnedIds != null &&
        !const SetEquality<String>().equals(
          pinnedIds.toSet(),
          _pinned.map((m) => m.id).toSet(),
        )) {
      unawaited(_loadPinned());
    }
  }

  Future<void> _refreshMessageStatuses() async {
    if (!mounted || _refreshingStatuses || _chatUnavailable || !_foreground)
      return;
    final generation = _loadGeneration;
    final batches = _reconciler.batches(
      _messages.reversed,
      selectedReply: _replyTo,
    );
    if (batches.isEmpty) return;
    _refreshingStatuses = true;
    try {
      // Do not truncate at 100: users can have many earlier pages loaded.
      for (final ids in batches) {
        final res = await _api.post('/messages/statuses', {
          'chat_id': widget.chatId,
          'message_ids': ids,
        });
        if (!mounted || generation != _loadGeneration || !_foreground) return;
        _applyMessageUpdate(MessageSyncResult.fromJson(res));
      }
    } on ApiException catch (error) {
      if ([403, 404].contains(error.statusCode)) _showChatUnavailable();
    } catch (_) {
      // Every batch is reconciled again next cycle; missed polls lose no state.
    } finally {
      _refreshingStatuses = false;
    }
  }

  Future<void> _pollNewMessages() async {
    if (!mounted || _polling || _loading || _historyMode) return;
    _polling = true;
    final generation = _loadGeneration;
    try {
      final query = <String, String>{};
      if (_lastMessageId != null) query['after_id'] = _lastMessageId!;
      final res = await _api.get('/messages/${widget.chatId}', query: query);
      if (!mounted ||
          _searchMode ||
          _historyMode ||
          generation != _loadGeneration)
        return;
      final list = (res['messages'] as List? ?? [])
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList();
      if (list.isNotEmpty) {
        _lastMessageId = list.last.id;
        final atBottom =
            !_scrollCtrl.hasClients ||
            _scrollCtrl.position.maxScrollExtent - _scrollCtrl.offset < 160;
        setState(() => _mergeMessages(list));
        if (atBottom) _scrollToBottom();
        _markChatRead();
      }
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  MessageModel _sentMessage(Map<String, dynamic> payload, MessageModel? reply) {
    final message = MessageModel.fromJson({
      'reply_to_id': reply?.id,
      ...payload,
    });
    // Trust the current server's privacy-filtered snapshot. Only older servers
    // with abbreviated send responses need the locally selected quote fallback.
    return message.replyTo != null || reply == null
        ? message
        : message.copyWith(replyTo: reply.asReplyPreview);
  }

  void _startSlowModeTimer(int seconds) {
    _slowModeTimer?.cancel();
    setState(() => _slowModeRemaining = seconds);
    _slowModeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_slowModeRemaining <= 1) {
        timer.cancel();
        setState(() => _slowModeRemaining = 0);
      } else {
        setState(() => _slowModeRemaining--);
      }
    });
  }

  void _handleSlowModeError(String message) {
    final match = RegExp(r'(\d+)').firstMatch(message);
    final secs = match != null ? int.tryParse(match.group(1)!) ?? _slowModeDelay : _slowModeDelay;
    _startSlowModeTimer(secs > 0 ? secs : 10);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _sendText({DateTime? scheduledAt}) async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending || !_can('send_messages')) return;
    if (_slowModeRemaining > 0 && (_myRole != 'owner' && _myRole != 'admin')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لطفاً $_slowModeRemaining ثانیه دیگر برای ارسال پیام صبر کنید.')),
      );
      return;
    }
    final reply = _replyTo;
    final sendSpoiler = _isSpoiler;
    setState(() => _sending = true);
    try {
      final body = <String, dynamic>{
        'chat_id': widget.chatId,
        'content': text,
        'message_type': 'text',
        'is_spoiler': sendSpoiler,
      };
      if (reply != null) body['reply_to_id'] = reply.id;
      if (scheduledAt != null) {
        // Iran time fix: Flutter DateTime is local (e.g. Asia/Tehran +03:30).
        // toUtc().toIso8601String() sends UTC with 'Z', so backend stores correct UTC
        // and displays it back in local time via parseApiDateTime(...).toLocal().
        body['scheduled_at'] = scheduledAt.toUtc().toIso8601String();
      }
      final res = await _api.post('/messages/', body);
      if (!mounted) return;
      if (res['is_scheduled'] == true) {
        setState(() {
          _textCtrl.clear();
          _replyTo = null;
          _isSpoiler = false;
          _sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('پیام زمان‌بندی شد.')),
        );
        return;
      }
      final msg = _sentMessage(res, reply);
      setState(() {
        _mergeMessages([msg]);
        _textCtrl.clear();
        _replyTo = null;
        _isSpoiler = false;
        _sending = false;
      });
      if (_slowModeDelay > 0 && (_myRole != 'owner' && _myRole != 'admin')) {
        _startSlowModeTimer(_slowModeDelay);
      }
      if (_historyMode) await _loadMessages();
      if (!mounted) return;
      _scrollToBottom();
      ref.read(chatListProvider.notifier).refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      if (e.statusCode == 429) {
        _handleSlowModeError(e.message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _scheduleMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ابتدا متن پیام را وارد کنید')),
      );
      return;
    }
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(minutes: 5)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 10))),
    );
    if (pickedTime == null || !mounted) return;

    final scheduledDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (scheduledDateTime.isBefore(DateTime.now().add(const Duration(seconds: 30)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('زمان انتخاب‌شده باید در آینده باشد')),
      );
      return;
    }

    _sendText(scheduledAt: scheduledDateTime);
  }

  void _openScheduledSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ScheduledMessagesSheet(
        chatId: widget.chatId,
        api: _api,
      ),
    );
  }

  Future<void> _pickAndSendFile() async {
    if (_sending || !_can('send_files')) return;
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null || !mounted) return;

    final file = File(result.files.single.path!);
    final fileName = result.files.single.name;
    final reply = _replyTo;

    bool sendSpoiler = _isSpoiler;
    setState(() => _sending = true);
    try {
      final upload = await _api.uploadFile('/media/upload', file);
      final mediaId = upload['id'] as String;
      final body = <String, dynamic>{
        'chat_id': widget.chatId,
        'message_type': 'file',
        'media_id': mediaId,
        'content': fileName,
        'is_spoiler': sendSpoiler,
      };
      if (reply != null) body['reply_to_id'] = reply.id;
      final res = await _api.post('/messages/', body);
      if (!mounted) return;
      final msg = _sentMessage({
        ...res,
        'media_id': mediaId,
        'media_url': '/api/v1/media/$mediaId',
        'message_type': 'file',
        'original_name': fileName,
        'is_spoiler': sendSpoiler,
      }, reply);
      setState(() {
        _mergeMessages([msg]);
        _replyTo = null;
        _isSpoiler = false;
        _sending = false;
      });
      if (_slowModeDelay > 0 && (_myRole != 'owner' && _myRole != 'admin')) {
        _startSlowModeTimer(_slowModeDelay);
      }
      if (_historyMode) await _loadMessages();
      _scrollToBottom();
      if (mounted) ref.read(chatListProvider.notifier).refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      if (e.statusCode == 429) {
        _handleSlowModeError(e.message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _pickAndSendMedia(
    ImageSource source, {
    bool isVideo = false,
    bool viewOnce = false,
  }) async {
    if (_sending || !_can(isVideo ? 'send_videos' : 'send_photos')) return;
    final picker = ImagePicker();
    final XFile? picked = isVideo
        ? await picker.pickVideo(source: source)
        : await picker.pickImage(
            source: source,
            maxWidth: 4096,
            imageQuality: 95,
          );
    if (picked == null || !mounted) return;

    // Internal editor (Telegram-like): crop/draw/text for photos,
    // trim/mute for videos. Back = cancel the send.
    File sendFile = File(picked.path);
    bool videoMuted = false;
    Map<String, String>? trimFields;
    if (!isVideo) {
      final edited = await Navigator.of(context).push<File>(
        MaterialPageRoute(builder: (_) => PhotoEditorScreen(imageFile: sendFile)),
      );
      if (edited == null || !mounted) return;
      sendFile = edited;
    } else {
      final edited = await Navigator.of(context).push<EditedVideo>(
        MaterialPageRoute(builder: (_) => VideoEditorScreen(videoFile: sendFile)),
      );
      if (edited == null || !mounted) return;
      sendFile = edited.file;
      videoMuted = edited.muted;
      if (edited.isTrimmed) {
        trimFields = {
          'trim_start_ms': edited.startMs.toString(),
          'trim_end_ms': edited.endMs.toString(),
        };
      }
    }

    bool sendViewOnce = viewOnce;
    bool sendSpoiler = _isSpoiler;
    if (!isVideo) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              ListTile(
                leading: const Icon(Icons.send),
                title: const Text('ارسال معمولی'),
                onTap: () => Navigator.pop(ctx, 'normal'),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined, color: Colors.purple),
                title: const Text('ارسال عکس با اسپویلر (مخفی)'),
                onTap: () => Navigator.pop(ctx, 'spoiler'),
              ),
              if (_can('send_view_once_photos'))
                ListTile(
                  leading: const Icon(Icons.timer, color: Colors.orange),
                  title: Text(MediaLabels.of(ctx).viewOnce),
                  subtitle: Text(MediaLabels.of(ctx).disappears),
                  onTap: () => Navigator.pop(ctx, 'once'),
                ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('لغو'),
                onTap: () => Navigator.pop(ctx, 'cancel'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (choice == null || choice == 'cancel' || !mounted) return;
      if (choice == 'spoiler') sendSpoiler = true;
      if (choice == 'once') sendViewOnce = true;
    } else {
      if (!sendSpoiler) {
        final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                ListTile(
                  leading: const Icon(Icons.send),
                  title: const Text('ارسال معمولی'),
                  onTap: () => Navigator.pop(ctx, 'normal'),
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined, color: Colors.purple),
                  title: const Text('ارسال ویدیو با اسپویلر (مخفی)'),
                  onTap: () => Navigator.pop(ctx, 'spoiler'),
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('لغو'),
                  onTap: () => Navigator.pop(ctx, 'cancel'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (choice == null || choice == 'cancel' || !mounted) return;
        if (choice == 'spoiler') sendSpoiler = true;
      }
    }

    final reply = _replyTo;
    setState(() => _sending = true);
    try {
      final upload = await _api.uploadFile('/media/upload', sendFile, fields: trimFields);
      final mediaId = upload['id'] as String;
      final mediaType =
          upload['media_type'] as String? ?? (isVideo ? 'video' : 'image');
      final body = <String, dynamic>{
        'chat_id': widget.chatId,
        'message_type': mediaType,
        'media_id': mediaId,
        'content': '',
        'is_view_once': sendViewOnce,
        'is_spoiler': sendSpoiler,
        if (isVideo && videoMuted) 'is_muted': true,
      };
      if (reply != null) body['reply_to_id'] = reply.id;
      final res = await _api.post('/messages/', body);
      if (!mounted) return;
      final msg = _sentMessage({
        ...res,
        'media_id': mediaId,
        'media_url': sendViewOnce ? null : '/api/v1/media/$mediaId',
        'message_type': mediaType,
        'is_view_once': sendViewOnce,
        'is_spoiler': sendSpoiler,
        if (isVideo && videoMuted) 'is_muted': true,
      }, reply);
      setState(() {
        _mergeMessages([msg]);
        _replyTo = null;
        _isSpoiler = false;
        _sending = false;
      });
      if (_historyMode) await _loadMessages();
      _scrollToBottom();
      if (mounted) ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _toggleVoiceRecord() async {
    if (_sending || (!_isRecording && !_can('send_voice'))) return;
    if (_isRecording) {
      final file = await _voice.stopRecording();
      if (!mounted) return;
      setState(() => _isRecording = false);
      if (file == null) return;
      if (!_can('send_voice')) {
        await _voice.cancelRecording();
        return;
      }
      final reply = _replyTo;
      setState(() => _sending = true);
      try {
        final upload = await _api.uploadFile('/media/upload', file);
        final mediaId = upload['id'] as String;
        final body = <String, dynamic>{
          'chat_id': widget.chatId,
          'message_type': 'voice',
          'media_id': mediaId,
          'content': '',
        };
        if (reply != null) body['reply_to_id'] = reply.id;
        final res = await _api.post('/messages/', body);
        if (!mounted) return;
        final msg = _sentMessage({
          ...res,
          'media_id': mediaId,
          'media_url': '/api/v1/media/$mediaId',
          'message_type': 'voice',
        }, reply);
        setState(() {
          _mergeMessages([msg]);
          _replyTo = null;
          _sending = false;
        });
        if (_historyMode) await _loadMessages();
        _scrollToBottom();
        if (mounted) ref.read(chatListProvider.notifier).refresh();
      } catch (e) {
        if (!mounted) return;
        setState(() => _sending = false);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    } else {
      await _playback.pause();
      final ok = await _voice.startRecording();
      if (!mounted) return;
      if (ok && !_can('send_voice')) {
        await _voice.cancelRecording();
        return;
      }
      if (ok) {
        setState(() => _isRecording = true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('دسترسی میکروفون لازم است')),
        );
      }
    }
  }

  Future<void> _cancelVoiceRecord() async {
    await _voice.cancelRecording();
    if (!mounted) return;
    setState(() => _isRecording = false);
  }

  // --- Telegram-like reactions ---
  Future<void> _toggleReaction(MessageModel msg, String emoji) async {
    try {
      await _api.post('/reactions/${msg.id}/reaction', {'emoji': emoji});
      // Local optimistic toggle: update reactions list immediately, then refresh from server
      // For simplicity, trigger a status refresh which will pull reactions via payloads
      unawaited(_refreshMessageStatuses());
      // Also poll messages to get updated reactions quickly
      final res = await _api.get('/messages/${widget.chatId}', query: {'from_id': msg.id});
      if (!mounted) return;
      final list = (res['messages'] as List? ?? []).map((e) => MessageModel.fromJson(e as Map<String, dynamic>)).toList();
      if (list.isNotEmpty) {
        setState(() {
          for (final updated in list) {
            final idx = _messages.indexWhere((m) => m.id == updated.id);
            if (idx != -1) _messages[idx] = updated;
          }
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _showReactionPicker(MessageModel msg) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => const QuickReactionSheet(),
    );
    if (emoji != null && mounted) await _toggleReaction(msg, emoji);
  }

  // --- Telegram-like stickers ---
  Future<void> _showStickerPicker() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StickerPicker(
        api: _api,
        onStickerSelected: (sticker) async {
          Navigator.pop(ctx);
          await _sendSticker(sticker);
        },
      ),
    );
  }

  Future<void> _sendSticker(dynamic sticker) async {
    if (_sending || !_can('send_messages')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('امکان ارسال استیکر در این چت وجود ندارد')));
      return;
    }
    final reply = _replyTo;
    setState(() => _sending = true);
    try {
      // sticker is StickerModel or map with id/media
      final stickerId = sticker is Map ? sticker['id'] : sticker.id;
      final emoji = sticker is Map ? sticker['emoji'] : sticker.emoji;
      // If sticker has media_id, use it; else send content emoji
      String? mediaId;
      if (sticker is Map && sticker['media_id'] != null) mediaId = sticker['media_id'] as String;
      else if (sticker is! Map && sticker.mediaId != null) mediaId = sticker.mediaId;
      else if (sticker is! Map && sticker.fileUrl != null) {
        // For seeded packs we may have url only - send as sticker via content fallback
      }
      final body = <String, dynamic>{
        'chat_id': widget.chatId,
        'message_type': 'sticker',
        'content': emoji ?? '🙂',
      };
      if (mediaId != null) body['media_id'] = mediaId;
      // If no mediaId but fileUrl exists, we send without media and server will fallback to display emoji
      if (reply != null) body['reply_to_id'] = reply.id;
      final res = await _api.post('/messages/', body);
      if (!mounted) return;
      final msg = _sentMessage(res, reply);
      setState(() {
        _mergeMessages([msg]);
        _replyTo = null;
        _sending = false;
      });
      _scrollToBottom();
      if (mounted) ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // --- Telegram-like GIFs ---
  Future<void> _showGifPicker() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GifPicker(
        api: _api,
        onGifSelected: (gif) async {
          Navigator.pop(ctx);
          await _sendGif(gif);
        },
      ),
    );
  }

  Future<void> _sendGif(dynamic gif) async {
    if (_sending || !_can('send_messages')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('امکان ارسال گیف وجود ندارد')));
      return;
    }
    final reply = _replyTo;
    setState(() => _sending = true);
    try {
      // gif is SavedGif (has mediaId or gif_url) – online GIFs are no longer offered.
      String? mediaId;
      String? gifUrl;
      String? title;
      if (gif is Map) {
        mediaId = gif['media_id'] as String?;
        gifUrl = gif['gif_url'] as String? ?? gif['url'] as String?;
        title = gif['title'] as String?;
      } else {
        // GifModel
        try { mediaId = (gif as dynamic).mediaId as String?; } catch (_) {}
        try { gifUrl = (gif as dynamic).gifUrl as String?; } catch (_) {}
        try { title = (gif as dynamic).title as String?; } catch (_) {}
        try { gifUrl ??= (gif as dynamic).previewUrl as String?; } catch (_) {}
      }
      final body = <String, dynamic>{
        'chat_id': widget.chatId,
        'message_type': 'gif',
        'content': (title?.isNotEmpty == true ? title : null) ?? gifUrl ?? 'GIF',
      };
      if (mediaId != null && mediaId.isNotEmpty) {
        body['media_id'] = mediaId;
      } else if (gifUrl != null && gifUrl.isNotEmpty) {
        // fallback: send URL as content; backend will still create gif message
        body['content'] = gifUrl;
      } else {
        throw Exception('گیف انتخاب‌شده فاقد اطلاعات است');
      }
      if (reply != null) body['reply_to_id'] = reply.id;
      final res = await _api.post('/messages/', body);
      if (!mounted) return;
      final msg = _sentMessage({
        ...res,
        // Hydrate media_url for local preview when backend omits it but we have the external URL
        if ((res['media_url'] == null || (res['media_url'] as String).isEmpty) && gifUrl != null && !gifUrl.startsWith('/')) 'media_url': gifUrl,
        if (res['media_id'] == null && mediaId != null) 'media_id': mediaId,
      }, reply);
      setState(() {
        _mergeMessages([msg]);
        _replyTo = null;
        _sending = false;
      });
      _scrollToBottom();
      if (mounted) ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted && _sending) setState(() => _sending = false);
    }
  }

  Future<void> _makeGifFromVideo() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
    if (video == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final upload = await _api.uploadFile('/media/upload', File(video.path));
      final mediaId = upload['id'] as String?;
      if (mediaId == null || mediaId.isEmpty) throw Exception('آپلود ویدیو ناموفق بود');
      // /gifs/make returns {ok:true, media_id, gif_url} – not {gif:{}}
      Map<String, dynamic> res;
      try {
        res = await _api.post('/gifs/make', {'media_id': mediaId, 'title': 'Converted GIF'});
      } catch (_) {
        // If make endpoint fails, fall back to sending video as gif directly
        res = {'media_id': mediaId, 'gif_url': '/api/v1/media/$mediaId'};
      }
      final outMediaId = (res['media_id'] as String?) ?? mediaId;
      final gifUrl = res['gif_url'] as String? ?? res['url'] as String? ?? '/api/v1/media/$outMediaId';
      final gifMap = res['gif'] as Map<String, dynamic>?;
      if (gifMap != null) {
        await _sendGif(gifMap);
        return;
      }
      // Fallback: optionally save to saved GIFs for future reuse (best-effort)
      try {
        await _api.post('/gifs/save', {'media_id': outMediaId, 'gif_url': gifUrl, 'preview_url': gifUrl, 'title': 'GIF از ویدیو'});
      } catch (_) {}
      // Direct send as gif message (most reliable, avoids double-save crash)
      final reply = _replyTo;
      final body = <String, dynamic>{
        'chat_id': widget.chatId,
        'message_type': 'gif',
        'media_id': outMediaId,
        'content': 'GIF',
      };
      if (reply != null) body['reply_to_id'] = reply.id;
      final msgRes = await _api.post('/messages/', body);
      if (!mounted) return;
      final msg = _sentMessage({...msgRes, 'media_id': outMediaId, 'media_url': '/api/v1/media/$outMediaId', 'message_type': 'gif'}, reply);
      setState(() {
        _mergeMessages([msg]);
        _replyTo = null;
        _sending = false;
      });
      _scrollToBottom();
      if (mounted) ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ساخت گیف ناموفق: $e')));
      }
    } finally {
      if (mounted && _sending) setState(() => _sending = false);
    }
  }

  // --- Telegram-like round video messages (video_note) ---
  Future<void> _recordVideoNote() async {
    if (_sending || !_can('send_messages')) return;
    // Telegram round videos are portrait, max 60s, circular. We reuse gallery/camera video picker and send as video_note.
    final picker = ImagePicker();
    final XFile? video = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 60));
    if (video == null || !mounted) return;
    final file = File(video.path);
    final reply = _replyTo;
    setState(() => _sending = true);
    try {
      final upload = await _api.uploadFile('/media/upload', file);
      final mediaId = upload['id'] as String;
      final body = <String, dynamic>{
        'chat_id': widget.chatId,
        'message_type': 'video_note',
        'media_id': mediaId,
        'content': '',
      };
      if (reply != null) body['reply_to_id'] = reply.id;
      final res = await _api.post('/messages/', body);
      if (!mounted) return;
      final msg = _sentMessage({...res, 'media_id': mediaId, 'media_url': '/api/v1/media/$mediaId', 'message_type': 'video_note'}, reply);
      setState(() {
        _mergeMessages([msg]);
        _replyTo = null;
        _sending = false;
      });
      _scrollToBottom();
      if (mounted) ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _reportCurrentChat() async {
    final targetType = _chatType == 'private' ? 'user' : 'chat';
    final targetUserId = _chatType == 'private' ? _otherUser?.id : null;
    await showDialog(
      context: context,
      builder: (_) => ReportDialog(
        api: _api,
        targetType: targetType == 'user' ? 'user' : 'group',
        targetUserId: targetUserId,
        targetChatId: widget.chatId,
        title: _displayTitle,
      ),
    );
  }

  Future<void> _reportMessage(MessageModel msg) async {
    await showDialog(
      context: context,
      builder: (_) => ReportDialog(
        api: _api,
        targetType: 'message',
        targetMessageId: msg.id,
        targetChatId: widget.chatId,
        title: 'پیام',
      ),
    );
  }

  Future<void> _deleteMessage(MessageModel msg, {required bool forAll}) async {
    try {
      await _api.post('/messages/${msg.id}/delete', {'for_all': forAll});
      if (!mounted) return;
      _applyMessageUpdate(MessageSyncResult(deletedIds: {msg.id}));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _clearHistory({required bool forAll}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(forAll ? 'حذف برای همه' : 'حذف فقط برای من'),
        content: Text(
          forAll
              ? 'پیام‌ها برای همه حذف می‌شوند.'
              : 'تاریخچه فقط برای شما پاک می‌شود.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لغو'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تایید'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.post('/messages/chat/${widget.chatId}/clear', {
        'for_all': forAll,
      });
      if (!mounted) return;
      setState(() {
        ++_loadGeneration;
        _reconciler.remove(
          _reconciler
              .batches(_messages, selectedReply: _replyTo)
              .expand((ids) => ids),
        );
        _messages.clear();
        _messageKeys.clear();
        // Keep the soft-deleted cursor to fetch the next message reliably.
        _loading = false;
        _replyTo = null;
        _hasEarlier = false;
        _historyMode = false;
        _pinned.clear();
        _pinnedIndex = 0;
      });
      unawaited(_loadPinned());
      ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _blockUser() async {
    _currentUserId ??= StorageService.getUserId();
    final other = _otherUser?.id;
    if (other == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('کاربری برای بلاک یافت نشد')),
        );
      }
      return;
    }
    try {
      await _api.post('/users/block/$other', {});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('کاربر بلاک شد')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _openPhoto(MessageModel message) async {
    if (_openingMedia || _reconciler.isUnavailable(message.id)) return;
    _openingMedia = true;
    try {
      await _playback.pause();
      if (!mounted) return;
      final route = MaterialPageRoute<void>(
        builder: (_) => PhotoViewerScreen(
          url: _mediaFullUrl(message.mediaId, existingUrl: message.mediaUrl),
          token: _authToken,
          caption: message.content,
        ),
      );
      _photoRoute = route;
      _photoMessageId = message.id;
      await Navigator.of(context).push(route);
    } finally {
      _openingMedia = false;
      _photoRoute = null;
      _photoMessageId = null;
    }
  }

  Future<void> _openViewOnce(MessageModel message) async {
    if (_openingMedia ||
        !message.isViewOnce ||
        message.viewedAt != null ||
        message.senderId == _currentUserId ||
        _reconciler.isUnavailable(message.id))
      return;
    _openingMedia = true;
    try {
      await _playback.pause();
      if (!mounted) return;
      final route = MaterialPageRoute<void>(
        builder: (_) => ViewOncePhotoScreen(
          loadPhoto: () =>
              _api.getBytes('/messages/${message.id}/view-once/media'),
          consumePhoto: () async {
            final result = await _api
                .post('/messages/${message.id}/view-once', {})
                .timeout(const Duration(seconds: 20));
            return parseApiDateTime(result['viewed_at'] as String)!;
          },
          onViewed: (viewedAt) {
            if (!mounted) return;
            setState(() {
              final index = _messages.indexWhere((m) => m.id == message.id);
              if (index != -1)
                _messages[index] = _messages[index].copyWith(
                  viewedAt: viewedAt,
                );
            });
          },
        ),
      );
      _photoRoute = route;
      _photoMessageId = message.id;
      await Navigator.of(context).push(route);
      if (mounted) _refreshMessageStatuses();
    } finally {
      _openingMedia = false;
      _photoRoute = null;
      _photoMessageId = null;
    }
  }

  void _showMessageActions(MessageModel msg) {
    if (_reconciler.isUnavailable(msg.id)) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: ['❤️', '👍', '😂', '😮', '😢', '🙏'].map((e) => InkWell(
                      onTap: () { Navigator.pop(sheetCtx); _toggleReaction(msg, e); },
                      borderRadius: BorderRadius.circular(24),
                      child: Container(width: 48, height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.08), shape: BoxShape.circle, border: Border.all(color: Colors.grey.withValues(alpha: 0.12))), child: Text(e, style: const TextStyle(fontSize: 24))),
                    )).toList(),
                  ),
                ),
                const Divider(height: 16),
                MessageActionsSheet(
                  message: msg,
                  canDeleteForAll: _canDelete(msg),
                  canReply: _can('send_messages'),
                  canPin: _canPinMessages,
                  canForward: _allowForwarding && !msg.isSecure,
                  canEdit: _canEdit(msg),
                  onEdit: () => _editMessage(msg),
                  onTogglePin: (pin) => _togglePin(msg, pin),
                  onReply: () { if (mounted && _can('send_messages') && !_reconciler.isUnavailable(msg.id)) setState(() => _replyTo = msg); },
                  onForward: () => _forwardMessage(msg),
                  onDelete: (forAll) => _deleteMessage(msg, forAll: forAll),
                ),
                ListTile(leading: const Icon(Icons.add_reaction_outlined), title: const Text('افزودن واکنش (بیشتر)'), onTap: () { Navigator.pop(sheetCtx); _showReactionPicker(msg); }),
                ListTile(leading: const Icon(Icons.report_outlined, color: Colors.orange), title: const Text('گزارش و بلاک'), subtitle: const Text('گزارش + بلاک همزمان', style: TextStyle(fontSize: 11, color: Colors.grey)), onTap: () { Navigator.pop(sheetCtx); _reportMessage(msg); }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openInvite(ChatInviteLink link) async {
    if (_openingInvite || _chatUnavailable) return;
    setState(() => _openingInvite = true);
    final labels = ChatLabels.of(context);
    try {
      await _playback.pause();
      if (!mounted) return;
      final response = await _api.post('/chats/invite-preview', {
        'invite_link': link.value,
      });
      if (!mounted) return;
      var invite = ChatInviteModel.fromJson(response);
      if (!invite.isMember) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => ChatInviteDialog(invite: invite, token: _authToken),
        );
        if (confirm != true || !mounted) return;
        final joined = await _api.post('/chats/join', {
          'invite_link': link.value,
        });
        if (!mounted) return;
        invite = ChatInviteModel.fromJson(joined);
      }
      unawaited(ref.read(chatListProvider.notifier).refresh());
      if (invite.id == widget.chatId) {
        unawaited(_loadChatInfo());
        return;
      }
      if (!mounted) return;
      setState(() => _openingInvite = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            chatId: invite.id,
            title: invite.title,
            chatType: invite.chatType,
            avatarUrl: invite.avatarUrl,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        final unavailable =
            error is ApiException &&
            [400, 403, 404, 410].contains(error.statusCode);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              unavailable ? labels.inviteUnavailable : labels.inviteFailed,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingInvite = false);
    }
  }

  Future<void> _pickAndSendMusic() async {
    if (_sending || !_can('send_files')) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'aac', 'ogg', 'wav', 'flac', 'opus', 'wma'],
    );
    if (result == null || result.files.single.path == null || !mounted) return;
    final file = File(result.files.single.path!);
    var name = result.files.single.name;
    name = name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
    String? artist;
    String title = name;
    if (name.contains(' - ')) {
      final parts = name.split(' - ');
      artist = parts.first.trim();
      title = parts.sublist(1).join(' - ').trim();
    }
    final reply = _replyTo;
    setState(() => _sending = true);
    try {
      final upload = await _api.uploadFile('/media/upload', file);
      final mediaId = upload['id'] as String;
      final body = <String, dynamic>{
        'chat_id': widget.chatId,
        'message_type': 'audio',
        'media_id': mediaId,
        'content': title,
        'audio_title': title,
        if (artist?.isNotEmpty == true) 'audio_artist': artist,
        'is_spoiler': _isSpoiler,
      };
      if (reply != null) body['reply_to_id'] = reply.id;
      final res = await _api.post('/messages/', body);
      if (!mounted) return;
      final msg = _sentMessage({
        ...res,
        'media_id': mediaId,
        'media_url': '/api/v1/media/$mediaId',
        'message_type': 'audio',
        'content': title,
        'audio_title': title,
        if (artist?.isNotEmpty == true) 'audio_artist': artist,
      }, reply);
      setState(() {
        _mergeMessages([msg]);
        _replyTo = null;
        _isSpoiler = false;
        _sending = false;
      });
      if (_historyMode) await _loadMessages();
      _scrollToBottom();
      if (mounted) ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _sendLocation() async {
    if (_sending || !_can('send_messages')) return;
    final picked = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (picked == null || !mounted) return;
    final reply = _replyTo;
    setState(() => _sending = true);
    try {
      final body = <String, dynamic>{
        'chat_id': widget.chatId,
        'message_type': picked['is_live'] == true ? 'live_location' : 'location',
        'latitude': picked['latitude'],
        'longitude': picked['longitude'],
        if ((picked['title'] as String?)?.isNotEmpty == true) 'location_title': picked['title'],
        if (picked['is_live'] == true) 'live_minutes': picked['live_minutes'] ?? 15,
      };
      if (reply != null) body['reply_to_id'] = reply.id;
      final res = await _api.post('/messages/', body);
      if (!mounted) return;
      final msg = _sentMessage(res, reply);
      setState(() {
        _mergeMessages([msg]);
        _replyTo = null;
        _sending = false;
      });
      if (picked['is_live'] == true) {
        _startLiveLocation(
          msg.id,
          Duration(minutes: (picked['live_minutes'] as int?) ?? 15),
        );
      }
      if (_historyMode) await _loadMessages();
      _scrollToBottom();
      if (mounted) ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// Polling-based live location: push our position every 20s until the
  /// sharing window ends (Telegram behaviour without a realtime socket).
  void _startLiveLocation(String messageId, Duration duration) {
    _liveLocationTimer?.cancel();
    _liveLocationMessageId = messageId;
    _liveLocationUntil = DateTime.now().add(duration);
    if (mounted) setState(() {});
    _liveLocationTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _pushLiveLocation());
    _pushLiveLocation();
  }

  Future<void> _pushLiveLocation() async {
    final id = _liveLocationMessageId;
    final until = _liveLocationUntil;
    if (id == null || until == null) return;
    if (DateTime.now().isAfter(until)) {
      _stopLiveLocation();
      return;
    }
    final result = await LocationService.current(
      timeout: const Duration(seconds: 12),
    );
    if (!mounted || !result.isSuccess || _liveLocationMessageId != id) return;
    try {
      final res = await _api.post('/messages/$id/live-location', {
        'latitude': result.position!.latitude,
        'longitude': result.position!.longitude,
      });
      if (!mounted) return;
      setState(() => _mergeMessages([MessageModel.fromJson(res)]));
    } catch (_) {
      // A transient failure must not kill the share; the next tick retries.
    }
  }

  Future<void> _stopLiveLocation({bool notifyServer = true}) async {
    final id = _liveLocationMessageId;
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
    _liveLocationMessageId = null;
    _liveLocationUntil = null;
    if (mounted) setState(() {});
    if (id == null || !notifyServer) return;
    try {
      final res = await _api.post('/messages/$id/live-location', {'stop': true});
      if (mounted) setState(() => _mergeMessages([MessageModel.fromJson(res)]));
    } catch (_) {}
  }

  Future<void> _sendEncryptedText() async {
    if (_sending || !_can('send_messages')) return;
    final textCtrl = TextEditingController(text: _textCtrl.text.trim());
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('متن پیام رمزدار'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          maxLines: 5,
          minLines: 1,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'متن...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(ctx, textCtrl.text.trim()), child: const Text('ادامه')),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    final lock = await EncryptDialog.show(context);
    if (lock == null || !mounted) return;
    final reply = _replyTo;
    setState(() => _sending = true);
    try {
      final cipher = EncryptionService.encryptText(text, lock['password']!);
      final body = <String, dynamic>{
        'chat_id': widget.chatId,
        'message_type': 'text',
        'content': cipher,
        'is_encrypted': true,
        if (lock['hint'] != null) 'encryption_hint': lock['hint'],
      };
      if (reply != null) body['reply_to_id'] = reply.id;
      final res = await _api.post('/messages/', body);
      if (!mounted) return;
      final msg = _sentMessage(res, reply);
      setState(() {
        _mergeMessages([msg]);
        _textCtrl.clear();
        _replyTo = null;
        _sending = false;
      });
      if (_historyMode) await _loadMessages();
      _scrollToBottom();
      if (mounted) ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// Whether this chat currently has a live secure conversation, so the menu
  /// can offer "continue" instead of "start". Leaving the secure page no
  /// longer erases it, so it can be resumed at any time.
  Future<void> _checkSecureSession() async {
    try {
      final res = await _api.get(
        '/messages/${widget.chatId}',
        query: const {'secure': '1', 'limit': '1'},
      );
      final has = (res['messages'] as List? ?? []).isNotEmpty;
      if (mounted && has != _hasSecureSession) {
        setState(() => _hasSecureSession = has);
      }
    } catch (_) {}
  }

  Future<void> _openSecureChat() async {
    await _playback.pause();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SecureChatScreen(chatId: widget.chatId, title: _chatTitle ?? widget.title),
      ),
    );
    if (!mounted) return;
    _refreshMessageStatuses();
    // The secure session may have been erased while we were inside it.
    _checkSecureSession();
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  ),
                  if (_can('send_photos'))
                    ListTile(
                      leading: const Icon(Icons.photo_library),
                      title: const Text('عکس از گالری'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendMedia(ImageSource.gallery);
                      },
                    ),
                  if (_can('send_photos'))
                    ListTile(
                      leading: const Icon(Icons.camera_alt),
                      title: const Text('دوربین'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendMedia(ImageSource.camera);
                      },
                    ),
                  if (_can('send_videos'))
                    ListTile(
                      leading: const Icon(Icons.videocam),
                      title: const Text('ویدیو'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendMedia(ImageSource.gallery, isVideo: true);
                      },
                    ),
                  if (_can('send_files'))
                    ListTile(
                      leading: const Icon(Icons.insert_drive_file),
                      title: const Text('ارسال فایل (اسناد، PDF، ZIP، PNG، TXT، ...)'),
                      subtitle: const Text('همه فرمت‌ها مانند تلگرام پشتیبانی می‌شوند', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendFile();
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.emoji_emotions_outlined, color: Colors.orange),
                    title: const Text('استیکر'),
                    subtitle: const Text('انتخاب از پک‌های آماده', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showStickerPicker();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.gif_box_outlined, color: Colors.blue),
                    title: const Text('GIF'),
                    subtitle: const Text('گیف‌های ذخیره‌شده شما (فایل .gif آپلود کنید)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showGifPicker();
                    },
                  ),
                  if (_can('send_files'))
                    ListTile(
                      leading: const Icon(Icons.music_note, color: Colors.purple),
                      title: const Text('موسیقی / فایل صوتی'),
                      subtitle: const Text('ارسال آهنگ با پخش‌کننده داخلی', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendMusic();
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined, color: Colors.green),
                    title: const Text('موقعیت مکانی'),
                    subtitle: const Text('ارسال لوکیشن ثابت یا زنده', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _sendLocation();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.enhanced_encryption_outlined, color: Colors.amber),
                    title: const Text('پیام رمزدار'),
                    subtitle: const Text('قفل متن با رمز (بدون رمز باز نمی‌شود)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _sendEncryptedText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.circle, color: Colors.teal),
                    title: const Text('پیام ویدیویی گرد'),
                    subtitle: const Text('ویدیو دایره‌ای مانند تلگرام (video_note)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _recordVideoNote();
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.visibility_off_outlined, color: Colors.purple),
                    title: const Text('حالت اسپویلر (مخفی تا زمان لمس)'),
                    subtitle: const Text('پیام بعدی محو نمایش داده می‌شود', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    value: _isSpoiler,
                    onChanged: (val) {
                      setSheetState(() {});
                      setState(() => _isSpoiler = val);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setBackgroundImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (picked == null) return;
    try {
      final upload = await _api.uploadFile('/media/upload', File(picked.path));
      final mediaId = upload['id'] as String;
      final url = _mediaFullUrl(mediaId, existingUrl: null);
      await _api.post('/chats/${widget.chatId}/background', {
        'type': 'image',
        'value': url,
      });
      setState(() {
        _bgImageUrl = url;
        _bgColor = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('کب‌دنارگ میظنت دش')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  /// Telegram-like edit rights: only the sender edits their own message
  /// (text or caption). Encrypted / view-once / secure messages are not editable.
  bool _canEdit(MessageModel msg) {
    if (_reconciler.isUnavailable(msg.id)) return false;
    if (msg.isViewOnce || msg.isEncrypted || msg.isSecure) return false;
    final mine = _chatType == 'channel'
        ? msg.author?.id == _currentUserId
        : msg.senderId == _currentUserId;
    if (mine != true) return false;
    if (msg.messageType == 'text') return (msg.content?.isNotEmpty ?? false);
    return ['image', 'video', 'file', 'audio', 'music', 'gif']
        .contains(msg.messageType);
  }

  Future<void> _editMessage(MessageModel msg) async {
    final ctrl = TextEditingController(text: msg.content ?? '');
    final isCaption = msg.messageType != 'text';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCaption ? 'ویرایش کپشن' : 'ویرایش پیام'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 5,
          minLines: 1,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'متن جدید...',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('ذخیره')),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    if (result == (msg.content ?? '')) return;
    try {
      await _api.post('/messages/${msg.id}/edit', {'content': result});
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == msg.id);
        if (i != -1) {
          _messages[i] = _messages[i].copyWith(content: result, isEdited: true, editedAt: DateTime.now());
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پیام ویرایش شد')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Tap on an @username mention → resolve to user → open their private chat.
  Future<void> _openMention(String username) async {
    try {
      final user = await _api.get('/users/by-username/$username');
      if (!mounted) return;
      final userId = user['id'] as String?;
      final displayName = user['display_name'] as String? ?? '@$username';
      if (userId == null) return;
      if (userId == _currentUserId) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('این خود شما هستید')));
        return;
      }
      final res = await _api.post('/chats/private', {'user_id': userId});
      if (!mounted) return;
      final chatId = res['chat_id'] as String?;
      if (chatId == null) return;
      if (chatId == widget.chatId) return;
      await _playback.pause();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(chatId: chatId, title: displayName, chatType: 'private'),
        ),
      );
    } catch (e) {
      if (mounted) {
        final msg = e is ApiException && e.statusCode == 404
            ? 'کاربر @$username یافت نشد'
            : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _forwardMessage(MessageModel msg) async {
    if (!_allowForwarding) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فوروارد از این گفتگو توسط مدیر بسته شده است')),
      );
      return;
    }
    final chatsRes = await _api.get('/chats/');
    final chats = (chatsRes['chats'] as List? ?? []);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: chats.length,
        itemBuilder: (_, i) {
          final c = chats[i];
          final title =
              c['title'] as String? ??
              (c['other_user'] != null
                  ? c['other_user']['display_name'] as String? ?? 'چت'
                  : 'چت');
          return ListTile(
            title: Text(title),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await _api.post('/messages/${msg.id}/forward', {
                  'target_chat_id': c['id'],
                });
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('فوروارد شد')));
                }
              } catch (e) {
                if (mounted) {
                  final msg = e is ApiException && e.statusCode == 403
                      ? 'فوروارد این پیام مجاز نیست (حریم خصوصی فرستنده یا مدیر)'
                      : e.toString();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                }
              }
            },
          );
        },
      ),
    );
  }

  void _showMoreMenu() {
    final isGroupOrChannel = _chatType == 'group' || _chatType == 'channel';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                if (isGroupOrChannel)
                  ListTile(
                    leading: Icon(_chatType == 'channel' ? Icons.campaign_outlined : Icons.group_outlined),
                    title: Text(_chatType == 'channel' ? _label('Channel information', 'اطلاعات کانال') : _label('Group information', 'اطلاعات گروه')),
                    onTap: () { Navigator.pop(ctx); _openManagement(); },
                  ),
                ListTile(
                  leading: const Icon(Icons.report_outlined, color: Colors.orange),
                  title: Text(_chatType == 'private' ? 'گزارش و بلاک کاربر' : 'گزارش گروه/کانال'),
                  subtitle: const Text('گزارش + بلاک همزمان (مانند تلگرام)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () { Navigator.pop(ctx); _reportCurrentChat(); },
                ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined, color: Colors.green),
                  title: Text(_hasSecureSession ? 'ادامه گفتگوی امن' : 'گفتگوی امن'),
                  subtitle: Text(
                    _hasSecureSession
                        ? 'گفتگوی امن باز است • برای ادامه ضربه بزنید'
                        : 'صفحه مشکی جدا • ضد اسکرین‌شات • بدون فوروارد و دانلود',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  onTap: () { Navigator.pop(ctx); _openSecureChat(); },
                ),
                ListTile(leading: const Icon(Icons.schedule), title: const Text('پیام‌های زمان‌بندی‌شده'), onTap: () { Navigator.pop(ctx); _openScheduledSheet(); }),
                ListTile(leading: const Icon(Icons.image), title: const Text('بک‌گراند تصویری'), onTap: () { Navigator.pop(ctx); _setBackgroundImage(); }),
                ListTile(leading: const Icon(Icons.search), title: const Text('جستجو در چت'), onTap: () { Navigator.pop(ctx); setState(() => _searchMode = true); }),
                const Divider(height: 12),
                ListTile(leading: const Icon(Icons.delete_outline), title: const Text('پاک کردن تاریخچه برای من'), onTap: () { Navigator.pop(ctx); _clearHistory(forAll: false); }),
                if (!isGroupOrChannel || _myRole == 'owner' || _capabilities['clear_history_for_all'] == true)
                  ListTile(
                    key: const ValueKey('clear-history-for-all'),
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text('پاک کردن برای همه', style: TextStyle(color: Colors.red)),
                    subtitle: const Text('برای همه اعضای چت حذف می‌شود', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    onTap: () { Navigator.pop(ctx); _clearHistory(forAll: true); },
                  ),
                if (_canPinMessages && _pinned.isNotEmpty)
                  ListTile(key: const ValueKey('unpin-all'), leading: const Icon(Icons.push_pin_outlined), title: Text(ChatLabels.of(context).unpinAll), onTap: () { Navigator.pop(ctx); _unpinAll(); }),
                if (!isGroupOrChannel)
                  ListTile(leading: const Icon(Icons.block, color: Colors.red), title: const Text('بلاک کاربر', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(ctx); _blockUser(); }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _label(String en, String fa) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;

  Future<void> _openManagement() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _chatType == 'channel'
            ? ChannelManagementScreen(
                chatId: widget.chatId,
                api: _api,
                token: _authToken,
              )
            : GroupManagementScreen(
                chatId: widget.chatId,
                api: _api,
                token: _authToken,
              ),
      ),
    );
    if (!mounted) return;
    await _loadChatInfo();
    if (mounted) ref.read(chatListProvider.notifier).refresh();
  }

  Future<void> _toggleMute() async {
    if (_muting) return;
    setState(() => _muting = true);
    try {
      final res = await _api.post('/chats/${widget.chatId}/mute', {
        'is_muted': !_isMuted,
      });
      if (mounted) setState(() => _isMuted = res['is_muted'] as bool);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _muting = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(authenticatedSessionProvider);
    if (session.userId == _sessionUserId) {
      _api = session.api;
      _authToken = session.token;
    }
    _currentUserId = _sessionUserId;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _searchMode
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'جستجو...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onSubmitted: (q) => _loadMessages(query: q),
              )
            : ChatHeader(
                title: _displayTitle,
                chatType: _chatType,
                otherUser: _otherUser,
                avatarUrl: _chatAvatarUrl,
                membersCount: _hasChatInfo ? _membersCount : null,
                onlineCount: _hasChatInfo ? _onlineCount : null,
                token: _authToken,
                onTap: _chatType == 'group' || _chatType == 'channel'
                    ? _openManagement
                    : _otherUser == null
                    ? null
                    : () async {
                        await _playback.pause();
                        if (!mounted || _otherUser == null) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                UserProfileScreen(userId: _otherUser!.id),
                          ),
                        );
                        if (mounted) unawaited(_loadChatInfo());
                      },
              ),
        actions: [
          if (_searchMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() => _searchMode = false);
                _loadMessages();
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: _showMoreMenu,
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: _bgImageUrl == null
              ? (_bgColor ?? theme.scaffoldBackgroundColor)
              : null,
          image: _bgImageUrl != null
              ? DecorationImage(
                  image: CachedNetworkImageProvider(
                    _bgImageUrl!,
                    headers: _authToken != null
                        ? {'Authorization': 'Bearer ${_authToken}'}
                        : null,
                  ),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (_openingInvite) const LinearProgressIndicator(minHeight: 2),
              if (_isSuspended)
                Container(
                  width: double.infinity,
                  color: Colors.red.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.block, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text('این گروه/کانال تعلیق شده است${_suspensionReason != null ? ': $_suspensionReason' : ''}', style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600))),
                      if (_myRole == 'owner')
                        TextButton(onPressed: _loadChatInfo, child: const Text('به‌روزرسانی', style: TextStyle(fontSize: 12))),
                    ],
                  ),
                ),
              if (_isClosed)
                Container(
                  width: double.infinity,
                  color: Colors.orange.withValues(alpha: 0.14),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.lock, color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text('این گروه/کانال بسته شده است${_closedReason != null ? ': $_closedReason' : ' (فقط مالک می‌تواند ارسال کند)'}', style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
              if (_pinned.isNotEmpty && !_searchMode)
                PinnedMessagesBar(
                  pinned: _pinned,
                  index: _pinnedIndex,
                  onTap: _tapPinnedBar,
                  onShowAll: _openPinnedMessages,
                  onUnpin: _canPinMessages
                      ? () => _togglePin(
                          _pinned[_pinnedIndex < _pinned.length
                              ? _pinnedIndex
                              : 0],
                          false,
                        )
                      : null,
                ),
              if (_liveLocationMessageId != null)
                Container(
                  width: double.infinity,
                  color: Colors.green.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    const Icon(Icons.share_location, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _liveLocationUntil != null
                            ? 'موقعیت زنده تا ${_liveLocationUntil!.hour.toString().padLeft(2, '0')}:${_liveLocationUntil!.minute.toString().padLeft(2, '0')} به‌اشتراک گذاشته می‌شود'
                            : 'موقعیت زنده در حال اشتراک است',
                        style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: _stopLiveLocation,
                      child: const Text('توقف', style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ]),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                            ElevatedButton(
                              onPressed: _chatUnavailable
                                  ? () => Navigator.of(context).maybePop()
                                  : () => _loadMessages(),
                              child: Text(
                                _chatUnavailable
                                    ? ChatLabels.of(context).close
                                    : MediaLabels.of(context).retry,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'هنوز پیامی نیست',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        itemCount: _messages.length + 1,
                        findChildIndexCallback: (key) {
                          if (key == const ValueKey('history-header')) return 0;
                          final index = _messages.indexWhere(
                            (m) => _messageKeys[m.id] == key,
                          );
                          return index == -1 ? null : index + 1;
                        },
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Center(
                              key: const ValueKey('history-header'),
                              child: _hasEarlier
                                  ? TextButton.icon(
                                      onPressed: _loadingEarlier
                                          ? null
                                          : _loadEarlier,
                                      icon: _loadingEarlier
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.expand_less),
                                      label: Text(
                                        MediaLabels.of(context).earlier,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            );
                          }
                          final msg = _messages[index - 1];
                          final isMine =
                              _chatType != 'channel' &&
                              msg.senderId == _currentUserId;
                          return GestureDetector(
                            key: _messageKeys.putIfAbsent(
                              msg.id,
                              () => GlobalKey(),
                            ),
                            onLongPress: () => _showMessageActions(msg),
                            onDoubleTap: () => _showReactionPicker(msg),
                            // Reply gestures do not own taps on media anymore.
                            onHorizontalDragEnd: (details) {
                              final velocity = details.primaryVelocity ?? 0;
                              if (velocity.abs() > 200 &&
                                  _can('send_messages')) {
                                setState(() => _replyTo = msg);
                              }
                            },
                            child: MessageBubble(
                              message: msg,
                              isMine: isMine,
                              currentUserId: _currentUserId,
                              reply: _replyPreviewFor(msg),
                              onReplyTap: msg.replyToId == null ? null : () => _jumpToReply(msg.replyToId!),
                              onOpenPhoto: () {
                                // For sticker/gif/video_note also allow viewing
                                if (msg.messageType == 'sticker' || msg.messageType == 'gif' || msg.messageType == 'video_note') return;
                                _openPhoto(msg);
                              },
                              onOpenViewOnce: () => _openViewOnce(msg),
                              onInviteTap: _openInvite,
                              onMentionTap: _openMention,
                              musicQueue: _messages.where((m) => m.isMusic && m.mediaId != null).toList(),
                              chatTitle: _chatTitle ?? widget.title,
                              coordinator: _playback,
                              highlighted: _highlightedMessageId == msg.id,
                              showSender: _chatType == 'group' || _chatType == 'channel',
                              mediaUrl: _mediaFullUrl(msg.mediaId, existingUrl: msg.mediaUrl),
                              token: _authToken,
                              onReactionTap: (emoji) => _toggleReaction(msg, emoji),
                              onAddReaction: () => _showReactionPicker(msg),
                            ),
                          );
                        },
                      ),
              ),
              if (_historyMode)
                TextButton.icon(
                  onPressed: () => _loadMessages(),
                  icon: const Icon(Icons.arrow_downward_rounded),
                  label: Text(MediaLabels.of(context).latest),
                ),
              if (_replyTo != null && !_searchMode) _buildReplyComposer(theme),
              const MiniMusicPlayer(),
              if (!_searchMode && !_chatUnavailable) _buildInputBar(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyComposer(ThemeData theme) {
    return Container(
      color: theme.cardColor,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: ReplyPreview(
              reply: _replyTo!.asReplyPreview,
              currentUserId: _currentUserId,
              token: _authToken,
            ),
          ),
          IconButton(
            tooltip: MediaLabels.of(context).cancelReply,
            onPressed: () => setState(() => _replyTo = null),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    if (!_can('send_messages')) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _chatType == 'channel'
                    ? _label(
                        'Broadcast channel — only authorized administrators can publish.',
                        'کانال انتشار — فقط مدیران مجاز می‌توانند پست منتشر کنند.',
                      )
                    : _label(
                        'Sending messages is not allowed in this group.',
                        'ارسال پیام در این گروه مجاز نیست.',
                      ),
                textAlign: TextAlign.center,
              ),
              if (_chatType == 'channel')
                TextButton.icon(
                  onPressed: _muting ? null : _toggleMute,
                  icon: Icon(
                    _isMuted
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_outlined,
                  ),
                  label: Text(
                    _isMuted
                        ? _label('Unmute', 'فعال کردن اعلان‌ها')
                        : _label('Mute', 'بی‌صدا'),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_slowModeRemaining > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      'حالت کند فعال است: $_slowModeRemaining ثانیه تا امکان ارسال بعدی',
                      style: const TextStyle(fontSize: 12, color: Colors.amber),
                    ),
                  ],
                ),
              ),
            // Compact bar – avoids overflow on 360dp screens: only attach + field + schedule/voice/send.
            // Sticker/GIF/video_note/spoiler live inside attach sheet to keep delete-for-all visible.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file_rounded),
                  tooltip: 'پیوست (عکس، فایل، استیکر، GIF، ویدیو گرد)',
                  onPressed: _sending ? null : _showAttachMenu,
                ),
                if (_isSpoiler)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10, right: 2),
                    child: GestureDetector(
                      onTap: () => setState(() => _isSpoiler = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.purple),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.visibility_off, size: 14, color: Colors.purple),
                            SizedBox(width: 4),
                            Text('اسپویلر', style: TextStyle(fontSize: 11, color: Colors.purple)),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextField(
                      controller: _textCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: _chatType == 'channel'
                            ? _label('Broadcast a post...', 'انتشار پست...')
                            : _label('Message...', 'پیام...'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: theme.scaffoldBackgroundColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.schedule_rounded),
                  tooltip: 'زمان‌بندی ارسال پیام',
                  onPressed: _sending ? null : _scheduleMessage,
                ),
                IconButton(
                  onPressed: _sending || (!_isRecording && !_can('send_voice'))
                      ? null
                      : _toggleVoiceRecord,
                  icon: Icon(
                    _isRecording ? Icons.stop_circle : Icons.mic_rounded,
                    color: _isRecording ? Colors.red : theme.colorScheme.primary,
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.hardEdge,
                  child: InkWell(
                    onTap: _sending ? null : _sendText,
                    onLongPress: _sending ? null : _scheduleMessage,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: _sending
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.send_rounded, color: theme.colorScheme.primary),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
