import 'package:equatable/equatable.dart';
import '../../core/utils/api_datetime.dart';
import 'user_model.dart';

class StoryModel extends Equatable {
  final String id;
  final String userId;
  final String storyType; // text | image | video
  final String? content;
  final String? mediaId;
  final String? mediaUrl;
  final String privacy;
  final int viewsCount;
  final bool viewerHasSeen;
  final UserModel? author;
  final DateTime? expiresAt;
  final DateTime createdAt;

  const StoryModel({
    required this.id,
    required this.userId,
    required this.storyType,
    this.content,
    this.mediaId,
    this.mediaUrl,
    this.privacy = 'everyone',
    this.viewsCount = 0,
    this.viewerHasSeen = false,
    this.author,
    this.expiresAt,
    required this.createdAt,
  });

  factory StoryModel.fromJson(Map<String, dynamic> json) {
    return StoryModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      storyType: json['story_type'] as String? ?? 'text',
      content: json['content'] as String?,
      mediaId: json['media_id'] as String?,
      mediaUrl: json['media_url'] as String?,
      privacy: json['privacy'] as String? ?? 'everyone',
      viewsCount: json['views_count'] as int? ?? 0,
      viewerHasSeen: json['viewer_has_seen'] as bool? ?? false,
      author: json['author'] is Map<String, dynamic>
          ? UserModel.fromJson(json['author'] as Map<String, dynamic>)
          : null,
      expiresAt: parseApiDateTime(json['expires_at'] as String?),
      createdAt: parseApiDateTime(json['created_at'] as String?) ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, userId, storyType, content, mediaId, mediaUrl, viewsCount, viewerHasSeen, expiresAt, createdAt];
}

class StoryGroup extends Equatable {
  final UserModel user;
  final List<StoryModel> stories;
  final bool hasUnseen;
  const StoryGroup({required this.user, required this.stories, this.hasUnseen = false});

  factory StoryGroup.fromJson(Map<String, dynamic> json) {
    return StoryGroup(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      stories: (json['stories'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(StoryModel.fromJson)
          .toList(),
      hasUnseen: json['has_unseen'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [user, stories, hasUnseen];
}
