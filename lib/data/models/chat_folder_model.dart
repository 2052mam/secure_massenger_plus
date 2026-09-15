import 'package:equatable/equatable.dart';

import 'chat_model.dart';

/// A Telegram style chat folder: rule based inclusion plus explicit chats.
class ChatFolderModel extends Equatable {
  final String id;
  final String name;
  final int position;
  final bool includePrivate;
  final bool includeGroups;
  final bool includeChannels;
  final bool includeArchived;
  final List<String> chatIds;

  const ChatFolderModel({
    required this.id,
    required this.name,
    this.position = 0,
    this.includePrivate = false,
    this.includeGroups = false,
    this.includeChannels = false,
    this.includeArchived = false,
    this.chatIds = const [],
  });

  factory ChatFolderModel.fromJson(Map<String, dynamic> json) {
    return ChatFolderModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      position: json['position'] as int? ?? 0,
      includePrivate: json['include_private'] as bool? ?? false,
      includeGroups: json['include_groups'] as bool? ?? false,
      includeChannels: json['include_channels'] as bool? ?? false,
      includeArchived: json['include_archived'] as bool? ?? false,
      chatIds: (json['chat_ids'] as List? ?? []).whereType<String>().toList(),
    );
  }

  Map<String, dynamic> toRequestBody() => {
    'name': name,
    'include_private': includePrivate,
    'include_groups': includeGroups,
    'include_channels': includeChannels,
    'include_archived': includeArchived,
    'chat_ids': chatIds,
  };

  ChatFolderModel copyWith({
    String? name,
    bool? includePrivate,
    bool? includeGroups,
    bool? includeChannels,
    bool? includeArchived,
    List<String>? chatIds,
  }) {
    return ChatFolderModel(
      id: id,
      name: name ?? this.name,
      position: position,
      includePrivate: includePrivate ?? this.includePrivate,
      includeGroups: includeGroups ?? this.includeGroups,
      includeChannels: includeChannels ?? this.includeChannels,
      includeArchived: includeArchived ?? this.includeArchived,
      chatIds: chatIds ?? this.chatIds,
    );
  }

  bool get hasRules =>
      includePrivate || includeGroups || includeChannels || chatIds.isNotEmpty;

  /// Archived chats stay hidden unless the folder explicitly asks for them.
  bool contains(ChatModel chat) {
    if (chat.isArchived && !includeArchived) return false;
    if (chatIds.contains(chat.id)) return true;
    switch (chat.chatType) {
      case 'private':
      case 'support':
      case 'saved':
        return includePrivate;
      case 'group':
        return includeGroups;
      case 'channel':
        return includeChannels;
    }
    return false;
  }

  @override
  List<Object?> get props => [
    id,
    name,
    position,
    includePrivate,
    includeGroups,
    includeChannels,
    includeArchived,
    chatIds,
  ];
}
