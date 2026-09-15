import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/message_model.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/screen_privacy_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_list_provider.dart';
import '../../widgets/chat/message_text.dart';

/// Secure chat mode — a separate black-theme page for the same chat.
/// While open:
///  - FLAG_SECURE blocks screenshots / screen recording (Android).
///  - No forward, download/save, copy or share actions exist.
///  - Media is rendered from memory only (no disk cache).
///
/// Leaving is NOT the same as ending the session (Telegram secret-chat
/// behaviour):
///  - Back / "minimise" simply returns to the normal chat. The secure
///    conversation stays alive, so you can talk to other people normally and
///    come back to it whenever you want.
///  - "End & erase" is an explicit, destructive action that wipes the secure
///    history for both sides.
class SecureChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String title;
  const SecureChatScreen({super.key, required this.chatId, required this.title});

  @override
  ConsumerState<SecureChatScreen> createState() => _SecureChatScreenState();
}

class _SecureChatScreenState extends ConsumerState<SecureChatScreen> {
  late ApiService _api;
  final List<MessageModel> _messages = [];
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _currentUserId;
  Timer? _pollTimer;
  Future<void> Function()? _releasePrivacy;

  /// Secure history is a separate stream on the backend (`?secure=1`).
  static const _secureQuery = {'secure': '1'};

  @override
  void initState() {
    super.initState();
    final session = ref.read(authenticatedSessionProvider);
    _api = session.api;
    _currentUserId = session.userId;
    _init();
  }

  Future<void> _init() async {
    try {
      _releasePrivacy = await ScreenPrivacyService.acquire();
    } catch (_) {}
    await _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    // Drop the decrypted copy from memory and release FLAG_SECURE. The
    // conversation itself is untouched — only this page's cache is cleared.
    _messages.clear();
    _releasePrivacy?.call();
    super.dispose();
  }

  List<MessageModel> _parse(Map<String, dynamic> res) =>
      (res['messages'] as List? ?? [])
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Future<void> _load() async {
    try {
      final res = await _api.get('/messages/${widget.chatId}', query: _secureQuery);
      if (!mounted) return;
      final list = _parse(res);
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _loading = false;
        _error = null;
      });
      _scrollToBottom();
      _markRead();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _poll() async {
    if (!mounted || _loading) return;
    try {
      final res = await _api.get('/messages/${widget.chatId}', query: _secureQuery);
      if (!mounted) return;
      final list = _parse(res);
      final known = _messages.map((m) => m.id).toSet();
      final fresh = list.where((m) => !known.contains(m.id)).toList();
      // The peer may have ended the session. Detect that only from an EMPTY
      // response: the endpoint returns a limited page, so "missing from this
      // page" does not mean "deleted" once history grows past one page.
      final erasedRemotely = list.isEmpty && _messages.isNotEmpty;
      if (erasedRemotely) {
        setState(_messages.clear);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('گفتگوی امن توسط طرف مقابل پاک شد')),
          );
        }
        return;
      }
      if (fresh.isNotEmpty) {
        setState(() => _messages.addAll(fresh));
        _scrollToBottom();
        _markRead();
      }
    } catch (_) {}
  }

  Future<void> _markRead() async {
    try {
      await _api.post('/messages/chat/${widget.chatId}/read', {});
      if (mounted) ref.read(chatListProvider.notifier).refresh();
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _inputCtrl.clear();
    setState(() => _sending = true);
    try {
      // POST /messages/ returns the created message object directly.
      final res = await _api.post('/messages/', {
        'chat_id': widget.chatId,
        'message_type': 'text',
        'content': text,
        'is_secure': true,
      });
      if (!mounted) return;
      try {
        final msg = MessageModel.fromJson(res);
        setState(() {
          _messages.add(msg);
          _sending = false;
        });
        _scrollToBottom();
      } catch (_) {
        setState(() => _sending = false);
        await _poll();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _deleteForMe(MessageModel msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('حذف پیام', style: TextStyle(color: Colors.white)),
        content: const Text('این پیام از گفتگوی امن پاک شود؟',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لغو')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.post('/messages/${msg.id}/delete', {});
      if (mounted) setState(() => _messages.removeWhere((m) => m.id == msg.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Only action allowed in secure mode: delete. No forward/copy/download/share.
  void _showSecureMenu(MessageModel msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.shield_outlined, color: Colors.greenAccent, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text('حالت امن: فوروارد، کپی و دانلود غیرفعال است',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('حذف پیام', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteForMe(msg);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Leave without destroying anything (the common case).
  void _minimise() {
    if (mounted) Navigator.pop(context);
  }

  /// Explicitly end the secure session and erase it for both sides.
  Future<void> _endAndErase() async {
    final erase = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('پایان و پاک‌سازی گفتگوی امن',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'تمام پیام‌های این گفتگوی امن برای هر دو طرف حذف می‌شود و قابل بازیابی نیست. '
          'گفتگوی عادی شما دست‌نخورده باقی می‌ماند.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لغو')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('پاک‌سازی و خروج'),
          ),
        ],
      ),
    );
    if (erase != true || !mounted) return;
    try {
      await _api.post('/messages/chat/${widget.chatId}/secure/clear', {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('پاک‌سازی ناموفق: $e')));
      }
      return;
    }
    if (!mounted) return;
    setState(_messages.clear);
    if (mounted) ref.read(chatListProvider.notifier).refresh();
    if (mounted) Navigator.pop(context);
  }

  /// Back button: leave the session running, exactly like closing a tab.
  Future<void> _onBack() async {
    if (_messages.isEmpty) {
      _minimise();
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'از گفتگوی امن خارج می‌شوید',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.chevron_left, color: Colors.greenAccent),
              title: const Text('بازگشت به گفتگوی عادی',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'گفتگوی امن باز می‌ماند و هر وقت خواستید برمی‌گردید',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              onTap: () => Navigator.pop(ctx, 'keep'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('پایان و پاک‌سازی کامل',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'همه پیام‌های امن برای هر دو طرف حذف می‌شود',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              onTap: () => Navigator.pop(ctx, 'erase'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'erase') {
      await _endAndErase();
    } else if (action == 'keep') {
      _minimise();
    }
    // Dismissing the sheet keeps the user in the secure chat.
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'بازگشت به گفتگوی عادی',
            onPressed: _onBack,
          ),
          title: Row(children: [
            const Icon(Icons.lock, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const Text('گفتگوی امن • ضد اسکرین‌شات',
                      style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
                ],
              ),
            ),
          ]),
          actions: [
            IconButton(
              tooltip: 'پایان و پاک‌سازی گفتگوی امن',
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              onPressed: _endAndErase,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: Colors.green.withValues(alpha: 0.12),
                child: const Row(children: [
                  Icon(Icons.shield_outlined, color: Colors.greenAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'اسکرین‌شات، فوروارد، کپی و دانلود در این صفحه غیرفعال است',
                      style: TextStyle(color: Colors.greenAccent, fontSize: 11),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                    : _error != null
                        ? Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                              const SizedBox(height: 8),
                              FilledButton(onPressed: _load, child: const Text('تلاش مجدد')),
                            ]),
                          )
                        : _messages.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'گفتگوی امن خالی است.\nپیام‌های اینجا جدا از گفتگوی عادی ذخیره می‌شوند.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white38),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.all(12),
                                itemCount: _messages.length,
                                itemBuilder: (_, i) => _SecureBubble(
                                  message: _messages[i],
                                  isMine: _messages[i].senderId == _currentUserId,
                                  onLongPress: () => _showSecureMenu(_messages[i]),
                                ),
                              ),
              ),
              Container(
                color: const Color(0xFF0A0A0A),
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 4,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'پیام امن...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white10,
                        border: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(20)),
                            borderSide: BorderSide.none),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.greenAccent,
                    child: IconButton(
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.send, color: Colors.black),
                      onPressed: _sending ? null : _send,
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecureBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final VoidCallback onLongPress;
  const _SecureBubble({required this.message, required this.isMine, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final bg = isMine ? const Color(0xFF1B5E20) : const Color(0xFF212121);
    final text = message.content?.trim().isNotEmpty == true
        ? message.content!.trim()
        : _nonTextLabel(message);
    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isMine ? 14 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 14),
            ),
            border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MessageText(
                text: text,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
              ),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock, size: 10, color: Colors.greenAccent),
                const SizedBox(width: 4),
                Text(
                  _time(message.createdAt),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  String _nonTextLabel(MessageModel m) {
    if (m.isEncrypted) return '🔒 پیام رمزدار (در گفتگوی عادی باز کنید)';
    switch (m.messageType) {
      case 'image':
        return '📷 عکس (نمایش رسانه در گفتگوی امن غیرفعال است)';
      case 'video':
        return '🎬 ویدیو (نمایش رسانه در گفتگوی امن غیرفعال است)';
      case 'voice':
        return '🎤 ویس (پخش رسانه در گفتگوی امن غیرفعال است)';
      case 'audio':
      case 'music':
        return '🎵 موسیقی (پخش رسانه در گفتگوی امن غیرفعال است)';
      case 'gif':
        return '🎞 گیف (نمایش رسانه در گفتگوی امن غیرفعال است)';
      case 'location':
        return '📍 موقعیت مکانی (در گفتگوی عادی باز کنید)';
      default:
        return '📎 فایل (دانلود در گفتگوی امن غیرفعال است)';
    }
  }

  String _time(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
