import 'package:equatable/equatable.dart';

class StickerModel extends Equatable {
  final String id;
  final String packId;
  final String? emoji;
  final String? fileUrl;
  final String? mediaId;
  final int? width;
  final int? height;
  final int position;

  const StickerModel({
    required this.id,
    required this.packId,
    this.emoji,
    this.fileUrl,
    this.mediaId,
    this.width,
    this.height,
    this.position = 0,
  });

  factory StickerModel.fromJson(Map<String, dynamic> json) {
    return StickerModel(
      id: json['id'] as String,
      packId: json['pack_id'] as String? ?? json['packId'] as String? ?? '',
      emoji: json['emoji'] as String?,
      fileUrl: json['file_url'] as String? ?? json['fileUrl'] as String?,
      mediaId: json['media_id'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      position: json['position'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [id, packId, emoji, fileUrl, mediaId];
}

class StickerPackModel extends Equatable {
  final String id;
  final String name;
  final String title;
  final String? thumbnailUrl;
  final bool isFeatured;
  final int stickersCount;
  final List<StickerModel>? stickers;

  const StickerPackModel({
    required this.id,
    required this.name,
    required this.title,
    this.thumbnailUrl,
    this.isFeatured = true,
    this.stickersCount = 0,
    this.stickers,
  });

  factory StickerPackModel.fromJson(Map<String, dynamic> json) {
    return StickerPackModel(
      id: json['id'] as String,
      name: json['name'] as String,
      title: json['title'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      isFeatured: json['is_featured'] as bool? ?? true,
      stickersCount: json['stickers_count'] as int? ?? 0,
      stickers: json['stickers'] is List ? (json['stickers'] as List).map((e) => StickerModel.fromJson(e as Map<String, dynamic>)).toList() : null,
    );
  }

  @override
  List<Object?> get props => [id, name, title];
}
