import 'package:equatable/equatable.dart';

class GifModel extends Equatable {
  final String id;
  final String? gifUrl;
  final String? previewUrl;
  final String? title;
  final String? externalId;
  final String? mediaId;

  const GifModel({
    required this.id,
    this.gifUrl,
    this.previewUrl,
    this.title,
    this.externalId,
    this.mediaId,
  });

  factory GifModel.fromJson(Map<String, dynamic> json) {
    return GifModel(
      id: json['id'] as String? ?? json['external_id'] as String? ?? '',
      gifUrl: json['gif_url'] as String? ?? json['url'] as String?,
      previewUrl: json['preview_url'] as String? ?? json['preview'] as String?,
      title: json['title'] as String?,
      externalId: json['external_id'] as String?,
      mediaId: json['media_id'] as String?,
    );
  }

  String get displayUrl => gifUrl ?? previewUrl ?? '';

  @override
  List<Object?> get props => [id, gifUrl, previewUrl, title];
}
