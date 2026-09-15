/// Links are parsed locally and resolved only by our authenticated backend.
/// Never launch securemessenger:// (or legacy t.me usernames) in a browser.
class ChatInviteLink {
  const ChatInviteLink._(this.uri);

  final Uri uri;
  String get value => uri.toString();

  static ChatInviteLink? tryParse(String text) {
    var value = text.trim();
    if (value.startsWith('t.me/')) value = 'https://$value';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        value.length > 2048 ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment)
      return null;
    final segments = uri.pathSegments;
    if (segments.length != 1 ||
        segments.first.isEmpty ||
        uri.path.endsWith('/'))
      return null;
    final target = segments.first;
    final isJoin = uri.scheme == 'securemessenger' && uri.host == 'join';
    final isPublic =
        (uri.scheme == 'securemessenger' && uri.host == 'public') ||
        (['http', 'https'].contains(uri.scheme) && uri.host == 't.me');
    if (isJoin && RegExp(r'^[a-zA-Z0-9_.-]{1,1024}$').hasMatch(target)) {
      return ChatInviteLink._(uri);
    }
    if (isPublic && RegExp(r'^[a-zA-Z0-9_]{3,30}$').hasMatch(target)) {
      return ChatInviteLink._(uri);
    }
    return null;
  }

  static final _candidates = RegExp(
    r'''securemessenger://[^\s<>"'\u200e\u200f\u202a-\u202e\u2066-\u2069]+|(?:https?://)?t\.me/[^\s<>"'\u200e\u200f\u202a-\u202e\u2066-\u2069]+''',
  );
  static final _trailingPunctuation = RegExp(r'[.,!?;:،؛؟\)\]\}»]+$');
  static final _insideWord = RegExp(r'[a-zA-Z0-9_@./:-]');

  static Iterable<ChatInviteMatch> findIn(String text) sync* {
    for (final match in _candidates.allMatches(text)) {
      // Do not turn evil.t.me/name or another URL's path into an app invite.
      if (match.start > 0 && _insideWord.hasMatch(text[match.start - 1]))
        continue;
      final value = match.group(0)!.replaceFirst(_trailingPunctuation, '');
      final link = tryParse(value);
      if (link != null)
        yield ChatInviteMatch(match.start, match.start + value.length, link);
    }
  }
}

class ChatInviteMatch {
  const ChatInviteMatch(this.start, this.end, this.link);
  final int start;
  final int end;
  final ChatInviteLink link;
}
