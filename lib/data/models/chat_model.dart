import '../../core/utils/api_datetime.dart';
import 'package:equatable/equatable.dart';

import 'user_model.dart';

class ChatModel extends Equatable {
  final String id;
  final String chatType; // private | group | channel | support
  final String? title;
  final String? username;
  final String? avatarUrl;
  final bool isPinned;
  final DateTime? pinnedAt;
  final bool isArchived;
  final bool isMuted;
  final bool isSponsored;
  final bool allowForwarding;
  final int slowModeDelay;
  final int unreadCount;
  final LastMessageModel? lastMessage;
  final DateTime updatedAt;
  final UserModel? otherUser;

  const ChatModel({
    required this.id,
    required this.chatType,
    this.title,
    this.username,
    this.avatarUrl,
    this.isPinned = false,
    this.pinnedAt,
    this.isArchived = false,
    this.isMuted = false,
    this.isSponsored = false,
    this.allowForwarding = true,
    this.slowModeDelay = 0,
    this.unreadCount = 0,
    this.lastMessage,
    required this.updatedAt,
    this.otherUser,
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    return ChatModel(
      id: json['id'] as String,
      chatType: json['chat_type'] as String? ?? 'private',
      title: json['title'] as String?,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isPinned: json['is_pinned'] as bool? ?? false,
      pinnedAt: parseApiDateTime(json['pinned_at'] as String?),
      isArchived: json['is_archived'] as bool? ?? false,
      isMuted: json['is_muted'] as bool? ?? false,
      isSponsored: json['is_sponsored'] as bool? ?? false,
      allowForwarding: json['allow_forwarding'] as bool? ?? true,
      slowModeDelay: json['slow_mode_delay'] as int? ?? 0,
      unreadCount: json['unread_count'] as int? ?? 0,
      lastMessage: json['last_message'] != null
          ? LastMessageModel.fromJson(
              json['last_message'] as Map<String, dynamic>,
            )
          : null,
      updatedAt:
          parseApiDateTime(json['updated_at'] as String?) ?? DateTime.now(),
      otherUser: json['other_user'] != null
          ? UserModel.fromJson(json['other_user'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Personal conversations for the default "Personal" folder (Telegram parity).
  bool get isPersonal =>
      chatType == 'private' || chatType == 'support' || chatType == 'saved';

  String get displayTitle {
    if (chatType == 'private' && otherUser != null) {
      return otherUser!.displayName;
    }
    return title ?? username ?? 'چت';
  }

  @override
  List<Object?> get props => [
    id,
    chatType,
    title,
    username,
    avatarUrl,
    isPinned,
    pinnedAt,
    isArchived,
    isMuted,
    isSponsored,
    allowForwarding,
    slowModeDelay,
    unreadCount,
    lastMessage,
    updatedAt,
    otherUser,
  ];
}

class LastMessageModel {
  final String? id;
  final String? content;
  final String? messageType;
  final String? senderId;
  final DateTime? createdAt;

  const LastMessageModel({
    this.id,
    this.content,
    this.messageType,
    this.senderId,
    this.createdAt,
  });

  factory LastMessageModel.fromJson(Map<String, dynamic> json) {
    return LastMessageModel(
      id: json['id'] as String?,
      content: json['content'] as String?,
      messageType: json['message_type'] as String?,
      senderId: json['sender_id'] as String?,
      createdAt: json['created_at'] != null
          ? parseApiDateTime(json['created_at'] as String?)
          : null,
    );
  }
}
