import 'package:equatable/equatable.dart';

import '../../core/utils/api_datetime.dart';

/// One photo of a user's profile album. Only users have albums.
class UserPhotoModel extends Equatable {
  final String id;
  final String photoUrl;
  final String? mediaId;
  final bool isMain;
  final DateTime? createdAt;

  const UserPhotoModel({
    required this.id,
    required this.photoUrl,
    this.mediaId,
    this.isMain = false,
    this.createdAt,
  });

  factory UserPhotoModel.fromJson(Map<String, dynamic> json) {
    return UserPhotoModel(
      id: json['id'] as String? ?? '',
      photoUrl: json['photo_url'] as String? ?? '',
      mediaId: json['media_id'] as String?,
      isMain: json['is_main'] as bool? ?? false,
      createdAt: parseApiDateTime(json['created_at'] as String?),
    );
  }

  static List<UserPhotoModel> listFrom(Map<String, dynamic> json) =>
      (json['photos'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(UserPhotoModel.fromJson)
          .where((photo) => photo.photoUrl.isNotEmpty)
          .toList();

  @override
  List<Object?> get props => [id, photoUrl, mediaId, isMain, createdAt];
}
