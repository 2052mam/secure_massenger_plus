import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/chat_invite_link.dart';

/// Telegram-like rich text: invite links + tappable @username mentions.
/// Link taps coexist with the chat's long-press menu and swipe-to-reply.
class MessageText extends StatefulWidget {
  const MessageText({
    super.key,
    required this.text,
    this.style,
    this.linkColor,
    this.onInviteTap,
    this.onMentionTap,
  });

  final String text;
  final TextStyle? style;
  final Color? linkColor;
  final ValueChanged<ChatInviteLink>? onInviteTap;
  /// Called with the username WITHOUT '@' when a mention is tapped.
  final ValueChanged<String>? onMentionTap;

  @override
  State<MessageText> createState() => _MessageTextState();
}

class _Span {
  final int start;
  final int end;
  final TapGestureRecognizer recognizer;
  final bool isMention;
  _Span(this.start, this.end, this.recognizer, this.isMention);
}

class _MessageTextState extends State<MessageText> {
  final List<TapGestureRecognizer> _recognizers = [];
  List<_Span> _spans = [];

  static final RegExp _mentionRegExp = RegExp(r'(^|[\s>«"\(\[])(@[a-zA-Z0-9_]{3,30})\b');

  @override
  void initState() {
    super.initState();
    _updateLinks();
  }

  @override
  void didUpdateWidget(covariant MessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.onInviteTap != widget.onInviteTap ||
        oldWidget.onMentionTap != widget.onMentionTap) {
      _updateLinks();
    }
  }

  void _updateLinks() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final spans = <_Span>[];
    if (widget.onInviteTap != null) {
      for (final match in ChatInviteLink.findIn(widget.text)) {
        final rec = TapGestureRecognizer()..onTap = () => widget.onInviteTap?.call(match.link);
        _recognizers.add(rec);
        spans.add(_Span(match.start, match.end, rec, false));
      }
    }
    if (widget.onMentionTap != null) {
      for (final m in _mentionRegExp.allMatches(widget.text)) {
        final handle = m.group(2)!;
        final start = m.start + (m.group(1)?.length ?? 0);
        final end = start + handle.length;
        // Don't double-link inside an invite link.
        if (spans.any((s) => start < s.end && end > s.start)) continue;
        final username = handle.substring(1);
        final rec = TapGestureRecognizer()..onTap = () => widget.onMentionTap?.call(username);
        _recognizers.add(rec);
        spans.add(_Span(start, end, rec, true));
      }
    }
    spans.sort((a, b) => a.start.compareTo(b.start));
    _spans = spans;
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_spans.isEmpty) {
      return Text(widget.text, style: widget.style);
    }
    final linkColor = widget.linkColor ?? Theme.of(context).colorScheme.primary;
    final children = <TextSpan>[];
    var position = 0;
    for (final s in _spans) {
      if (position < s.start) {
        children.add(TextSpan(text: widget.text.substring(position, s.start)));
      }
      children.add(
        TextSpan(
          text: widget.text.substring(s.start, s.end),
          style: TextStyle(
            color: s.isMention ? linkColor : linkColor,
            fontWeight: s.isMention ? FontWeight.w600 : null,
            decoration: s.isMention ? null : TextDecoration.underline,
          ),
          recognizer: s.recognizer,
        ),
      );
      position = s.end;
    }
    if (position < widget.text.length) {
      children.add(TextSpan(text: widget.text.substring(position)));
    }
    return Text.rich(TextSpan(children: children), style: widget.style);
  }
}
