class ChatInviteModel {
  const ChatInviteModel({
    required this.id,
    required this.chatType,
    required this.title,
    required this.membersCount,
    required this.isMember,
    this.description,
    this.avatarUrl,
  });

  final String id;
  final String chatType;
  final String title;
  final int membersCount;
  final bool isMember;
  final String? description;
  final String? avatarUrl;

  factory ChatInviteModel.fromJson(Map<String, dynamic> json) =>
      ChatInviteModel(
        id: json['id'] as String,
        chatType: json['chat_type'] as String,
        title: json['title'] as String? ?? '',
        membersCount: json['members_count'] as int? ?? 0,
        isMember: json['is_member'] as bool? ?? false,
        description: json['description'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}
