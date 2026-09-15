import 'package:equatable/equatable.dart';

import '../../core/utils/api_datetime.dart';
import 'user_model.dart';

/// One remembered search: a free text term and, when it was opened, the
/// person or channel it led to. Deleting a chat never deletes this entry, so
/// a user can always find someone again without remembering their ID.
class SearchHistoryItem extends Equatable {
  final String id;
  final String? query;
  final UserModel? user;
  final SearchHistoryChat? chat;
  final DateTime? createdAt;

  const SearchHistoryItem({
    required this.id,
    this.query,
    this.user,
    this.chat,
    this.createdAt,
  });

  factory SearchHistoryItem.fromJson(Map<String, dynamic> json) {
    return SearchHistoryItem(
      id: json['id'] as String? ?? '',
      query: json['query'] as String?,
      user: json['user'] is Map<String, dynamic>
          ? UserModel.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      chat: json['chat'] is Map<String, dynamic>
          ? SearchHistoryChat.fromJson(json['chat'] as Map<String, dynamic>)
          : null,
      createdAt: parseApiDateTime(json['created_at'] as String?),
    );
  }

  static List<SearchHistoryItem> listFrom(Map<String, dynamic> json) =>
      (json['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(SearchHistoryItem.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList();

  String get title =>
      user?.displayName ?? chat?.title ?? query ?? '';

  String? get subtitle {
    if (user != null) return user!.handle;
    if (chat?.username != null) return '@${chat!.username}';
    return query;
  }

  @override
  List<Object?> get props => [id, query, user, chat, createdAt];
}

class SearchHistoryChat extends Equatable {
  final String id;
  final String chatType;
  final String? title;
  final String? username;
  final String? avatarUrl;

  const SearchHistoryChat({
    required this.id,
    required this.chatType,
    this.title,
    this.username,
    this.avatarUrl,
  });

  factory SearchHistoryChat.fromJson(Map<String, dynamic> json) {
    return SearchHistoryChat(
      id: json['id'] as String? ?? '',
      chatType: json['chat_type'] as String? ?? 'channel',
      title: json['title'] as String?,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, chatType, title, username, avatarUrl];
}
