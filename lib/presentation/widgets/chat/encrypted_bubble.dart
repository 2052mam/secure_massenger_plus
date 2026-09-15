import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/media_utils.dart';
import '../../../data/models/message_model.dart';
import '../../../data/services/encryption_service.dart';
import '../../../data/services/storage_service.dart';
import 'message_text.dart';
import '../../../core/utils/chat_invite_link.dart';

/// Encrypted (password-protected) message bubble — spoiler-like locked content.
/// Supports text + photo/video/voice/file: ciphertext is stored on the server,
/// plaintext NEVER leaves the device without the password.
class EncryptedBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMine;
  final Color foreground;
  final ValueChanged<ChatInviteLink>? onInviteTap;
  final ValueChanged<String>? onMentionTap;
  final VoidCallback? onOpenPhoto;
  const EncryptedBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.foreground,
    this.onInviteTap,
    this.onMentionTap,
    this.onOpenPhoto,
  });

  @override
  State<EncryptedBubble> createState() => _EncryptedBubbleState();
}

class _EncryptedBubbleState extends State<EncryptedBubble> {
  String? _decryptedText;
  Uint8List? _decryptedMedia;
  bool _unlocking = false;
  String? _error;

  Future<void> _askPassword() async {
    final ctrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.lock_outline, size: 20, color: Colors.amber),
          SizedBox(width: 8),
          Text('پیام رمزدار'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.message.encryptionHint?.isNotEmpty == true)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('راهنما: ${widget.message.encryptionHint}',
                    style: const TextStyle(fontSize: 12)),
              ),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'رمز پیام',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key_outlined),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('باز کردن')),
        ],
      ),
    );
    if (password == null || password.isEmpty || !mounted) return;
    await _unlock(password);
  }

  Future<void> _unlock(String password) async {
    setState(() {
      _unlocking = true;
      _error = null;
    });
    try {
      final msg = widget.message;
      if (msg.messageType == 'text' || msg.mediaId == null) {
        final plain = EncryptionService.decryptText(msg.content ?? '', password);
        if (mounted) setState(() => _decryptedText = plain);
      } else {
        // Download encrypted bytes, decrypt in memory (never cached to disk).
        final url = resolveMediaUrl(msg.mediaId, existingUrl: msg.mediaUrl);
        final token = StorageService.getToken();
        final res = await http.get(Uri.parse(url),
            headers: {if (token != null) 'Authorization': 'Bearer $token'});
        if (res.statusCode != 200) throw Exception('دانلود فایل ناموفق بود');
        final plain = EncryptionService.decryptBytes(res.bodyBytes, password);
        if (mounted) setState(() => _decryptedMedia = plain);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'رمز نادرست است یا فایل آسیب دیده');
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final fg = widget.foreground;
    // Unlocked text
    if (_decryptedText != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Icon(Icons.lock_open_outlined, size: 14, color: Colors.green),
            const SizedBox(width: 4),
            Text('رمزگشایی شد', style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.7))),
          ]),
          const SizedBox(height: 4),
          MessageText(
            text: _decryptedText!,
            style: TextStyle(color: fg, fontSize: 15, height: 1.35),
            onInviteTap: widget.onInviteTap,
            onMentionTap: widget.onMentionTap,
          ),
        ],
      );
    }
    // Unlocked media (image preview; other types show open hint)
    if (_decryptedMedia != null) {
      if (msg.messageType == 'image') {
        return GestureDetector(
          onTap: widget.onOpenPhoto,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(_decryptedMedia!, width: 240, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 40)),
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_open_outlined, size: 32, color: Colors.green),
          const SizedBox(height: 6),
          Text('فایل رمزگشایی شد (${_decryptedMedia!.length} بایت)',
              style: TextStyle(color: fg, fontSize: 12)),
          const SizedBox(height: 4),
          Text('برای مشاهده، فایل را ذخیره کنید',
              style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11)),
        ],
      );
    }
    // Locked state
    return InkWell(
      onTap: _unlocking ? null : _askPassword,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.5), style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: _unlocking
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_outline, color: Colors.amber, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              msg.messageType == 'text' ? 'پیام رمزدار' : 'فایل رمزدار (${_typeName(msg.messageType)})',
              style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text('برای مشاهده، رمز را وارد کنید',
                style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11)),
            if (msg.encryptionHint?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text('راهنما: ${msg.encryptionHint}',
                  style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
            ],
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }

  String _typeName(String t) {
    switch (t) {
      case 'image':
        return 'عکس';
      case 'video':
        return 'ویدیو';
      case 'voice':
        return 'ویس';
      case 'audio':
      case 'music':
        return 'موسیقی';
      default:
        return 'فایل';
    }
  }
}

/// Dialog to compose an encrypted message: password + optional hint.
class EncryptDialog extends StatefulWidget {
  const EncryptDialog({super.key});
  static Future<Map<String, String?>?> show(BuildContext context) {
    return showDialog<Map<String, String?>?>(
      context: context,
      builder: (_) => const EncryptDialog(),
    );
  }

  @override
  State<EncryptDialog> createState() => _EncryptDialogState();
}

class _EncryptDialogState extends State<EncryptDialog> {
  final _passCtrl = TextEditingController();
  final _hintCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passCtrl.dispose();
    _hintCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.enhanced_encryption_outlined, color: Colors.amber),
        SizedBox(width: 8),
        Text('پیام رمزدار'),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'پیام با رمز شما قفل می‌شود. بدون رمز (حتی با دسترسی به گوشی) قابل خواندن نیست. رمز را فراموش نکنید!',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'رمز (حداقل ۴ کاراکتر)',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hintCtrl,
            decoration: const InputDecoration(
              labelText: 'راهنمای رمز (اختیاری، عمومی)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lightbulb_outline),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
        FilledButton(
          onPressed: () {
            if (_passCtrl.text.length < 4) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('رمز حداقل ۴ کاراکتر باشد')),
              );
              return;
            }
            Navigator.pop(context, {
              'password': _passCtrl.text,
              'hint': _hintCtrl.text.trim().isEmpty ? null : _hintCtrl.text.trim(),
            });
          },
          child: const Text('قفل و ارسال'),
        ),
      ],
    );
  }
}
